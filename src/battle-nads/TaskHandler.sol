//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { BattleNad, BattleArea, Ability, AbilityTracker, CombatTracker } from "./Types.sol";
import { Handler } from "./Handler.sol";
import { Names } from "./libraries/Names.sol";
import { Errors } from "./libraries/Errors.sol";
import { Events } from "./libraries/Events.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

import { SessionKey } from "lib/fastlane-contracts/src/common/relay/types/GasRelayTypes.sol";
import { GeneralReschedulingTask } from "lib/fastlane-contracts/src/common/relay/tasks/GeneralReschedulingTask.sol";

interface ICustomTaskManager {
    /// @notice Load balancing configuration for task scheduling
    /// @dev Manages task distribution across blocks
    struct LoadBalancer {
        /// @notice Current active block for small tasks
        uint64 activeBlockSmall;
        /// @notice Current active block for medium tasks
        uint64 activeBlockMedium;
        /// @notice Current active block for large tasks
        uint64 activeBlockLarge;
        /// @notice Target delay between task scheduling and execution
        uint32 targetDelay;
        /// @notice Rate at which delays should adjust
        uint32 targetGrowthRate;
    }

    function S_loadBalancer() external view returns (LoadBalancer memory);
}

// These are the entrypoint functions called by the tasks
contract TaskHandler is Handler, GeneralReschedulingTask {
    using StatSheet for BattleNad;
    using Names for BattleNad;

    address public immutable TASK_IMPLEMENTATION;

    constructor(
        address taskManager,
        address shMonad
    )
        Handler(taskManager, shMonad)
        GeneralReschedulingTask(taskManager, shMonad)
    {
        TASK_IMPLEMENTATION = address(this);
    }

    // Called by a task
    function processTurn(bytes32 characterID)
        external
        GasAbstracted
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment)
    {
        // Load character
        BattleNad memory attacker = _loadBattleNadInTask(characterID);

        // Only one combat task at a time
        if (msg.sender != _loadActiveTaskAddress(characterID)) {
            revert Errors.InvalidCaller(msg.sender);
        }

        // Handle turn
        uint256 targetBlock;
        (attacker, reschedule, targetBlock) = _handleCombatTurn(attacker);

        // Set reschedule lock for reimbursement call afterwards
        if (reschedule) {
            (attacker, reschedule) = _createOrRescheduleCombatTask(attacker, targetBlock);
            if (!reschedule) {
                emit Events.TaskNotScheduledInTaskHandler(20, attacker.id, block.number, targetBlock);
            }
        } else {
            _clearActiveTask(characterID);
        }

        // Store the data
        _storeBattleNad(attacker);

        // Rescheduling is handled by the task based on the return value of the function call.
        return (reschedule, nextBlock, maxPayment);
    }

    // Called by a task
    function processSpawn(bytes32 characterID)
        external
        GasAbstracted
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment)
    {
        // Load character
        BattleNad memory attacker = _loadBattleNadInTask(characterID);

        // Handle spawn
        uint256 targetBlock;
        (attacker, reschedule, targetBlock) = _handleSpawn(attacker);

        // Reschedule if necessary
        if (reschedule) {
            // Calculate the maximum payment and estimate
            (attacker, reschedule) = _createOrRescheduleSpawnTask(attacker, targetBlock);

            // Force kill the character if they can't maintain their task.
            if (!reschedule) {
                emit Events.TaskNotScheduledInTaskHandler(21, attacker.id, block.number, targetBlock);
                _forceKill(attacker);
                return (false, 0, 0);
            }
        } else {
            _clearActiveTask(characterID);
        }

        _storeBattleNad(attacker);
        return (reschedule, nextBlock, maxPayment);
    }

    function processAscend(bytes32 characterID) external GasAbstracted {
        // Load character
        BattleNad memory player = _loadBattleNadInTask(characterID);

        uint8 depth = player.stats.depth;
        uint8 x = player.stats.x;
        uint8 y = player.stats.y;

        address owner = owners[characterID];
        BattleArea memory area = _loadArea(depth, x, y);

        // Verify that the nad is still alive and not in combat
        if (player.isDead()) {
            (player, area) = _processDeathDuringDeceasedTurn(player, area);
            _storeArea(area, depth, x, y);
            _clearActiveTask(characterID);
            _storeBattleNad(player);
            return;
        } else if (player.isInCombat()) {
            _clearActiveTask(characterID);
            _storeBattleNad(player);
            return;
        }

        uint256 cashedOutShMONShares = _forceKill(player);

        area = _logAscend(player, area, cashedOutShMONShares);

        _storeArea(area, depth, x, y);

        if (_isValidAddress(owner)) {
            SafeTransferLib.safeTransfer(SHMONAD, owner, cashedOutShMONShares);
        }
    }

    // Called by a task
    function processAbility(bytes32 characterID)
        external
        GasAbstracted
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment)
    {
        // Load character
        BattleNad memory attacker = _loadBattleNadInTask(characterID);

        // Handle ability
        uint256 targetBlock;
        (attacker, reschedule, targetBlock) = _handleAbility(attacker);

        // Reschedule if necessary
        if (reschedule) {
            (attacker, reschedule) = _createOrRescheduleAbilityTask(attacker, targetBlock);
            if (!reschedule) {
                emit Events.TaskNotScheduledInTaskHandler(22, attacker.id, block.number, targetBlock);
            }
        }

        // If successful, store the data
        _storeBattleNad(attacker);
        return (reschedule, targetBlock, maxPayment);
    }

    function _loadBattleNadInTask(bytes32 characterID) internal view returns (BattleNad memory combatant) {
        // Load character
        combatant = _loadBattleNad(characterID, true);
        combatant.activeTask.taskAddress = msg.sender;
        combatant.owner = _abstractedMsgSender();
        if (!_isTask()) {
            revert Errors.InvalidCaller(msg.sender);
        }
    }

    function _createOrRescheduleCombatTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        override
        returns (BattleNad memory, bool)
    {
        if (!_isValidAddress(combatant.owner)) {
            revert Errors.CharacterNotOwned(combatant.id);
        }

        // Calculate the maximum payment
        bytes memory data = abi.encodeCall(this.processTurn, (combatant.id));

        // Create the task
        (bool success, bytes32 taskID) = _scheduleCallback(data, TASK_GAS, targetBlock, targetBlock + 65, true);

        if (success) {
            // Get the task address, flag for storage in the future
            address taskAddress = address(uint160(uint256(taskID)));
            if (taskAddress != address(0)) {
                _storeActiveTask(combatant.id, taskID);
            } else {
                _hackyUpdateTaskID(combatant.id, targetBlock);
            }
        } else {
            _clearActiveTask(combatant.id);
        }

        // Return combatant
        return (combatant, success);
    }

    function _createOrRescheduleSpawnTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        override
        returns (BattleNad memory, bool)
    {
        if (!_isValidAddress(combatant.owner)) {
            revert Errors.CharacterNotOwned(combatant.id);
        }

        // Calculate the maximum payment
        bytes memory data = abi.encodeCall(this.processSpawn, (combatant.id));

        // Create the task
        (bool success, bytes32 taskID) = _scheduleCallback(data, TASK_GAS, targetBlock, targetBlock + 65, true);

        // Return combatant
        return (combatant, success);
    }

    function _createOrRescheduleAbilityTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        override
        returns (BattleNad memory, bool)
    {
        if (!_isValidAddress(combatant.owner)) {
            revert Errors.CharacterNotOwned(combatant.id);
        }

        // Encode data
        bytes memory data = abi.encodeCall(this.processAbility, (combatant.id));

        // Create the task
        (bool success, bytes32 taskID) = _scheduleCallback(data, TASK_GAS, targetBlock, targetBlock + 65, true);

        if (success) {
            // Get the task address, flag for storage in the future
            address taskAddress = address(uint160(uint256(taskID)));
            if (taskAddress != address(0)) {
                combatant.activeAbility.taskAddress = taskAddress;
            }
            combatant.activeAbility.targetBlock = uint64(targetBlock);
            combatant.tracker.updateActiveAbility = true;
        } else {
            combatant.activeAbility.taskAddress = _EMPTY_ADDRESS;
            combatant.activeAbility.targetBlock = uint64(0);
            combatant.activeAbility.stage = 0;
            combatant.activeAbility.ability = Ability.None;
            combatant.tracker.updateActiveAbility = true;
        }

        // Return combatant
        return (combatant, success);
    }

    function _createOrRescheduleAscendTask(BattleNad memory combatant) internal override returns (BattleNad memory) {
        bytes memory data = abi.encodeCall(this.processAscend, (combatant.id));

        // Create the task
        (bool success, bytes32 taskID) = _scheduleCallback(data, TASK_GAS, block.number + 96, block.number + 192, true);
        if (success) {
            // Get the task address, flag for storage in the future
            address taskAddress = address(uint160(uint256(taskID)));
            // Rescheduling currently doesnt return a new taskID bc it hasnt been generated yet
            if (taskAddress != address(0)) {
                _storeActiveTask(combatant.id, taskID);
            }
        } else {
            _clearActiveTask(combatant.id);
        }
        return combatant;
    }

    function _restartCombatTask(BattleNad memory combatant) internal override returns (BattleNad memory, bool) {
        combatant.owner = _loadOwner(combatant.id);
        if (combatant.owner != _abstractedMsgSender()) {
            revert Errors.InvalidCaller(msg.sender);
        }
        bytes memory data = abi.encodeCall(this.processTurn, (combatant.id));

        // Create the task
        (bool success, bytes32 taskID) = _scheduleCallback(data, TASK_GAS, block.number + 1, block.number + 65, true);

        if (success) {
            // Get the task address, flag for storage in the future
            address taskAddress = address(uint160(uint256(taskID)));
            if (taskAddress != address(0)) {
                _storeActiveTask(combatant.id, taskID);
                return (combatant, true);
            }
        }
        return (combatant, false);
    }

    function _checkClearTasks(BattleNad memory combatant)
        internal
        override
        returns (bool hasActiveCombatTask, address activeTask)
    {
        if (!_isValidID(combatant.id)) {
            return (hasActiveCombatTask, activeTask);
        }

        bytes32 taskID = _loadActiveTaskID(combatant.id);
        activeTask = address(uint160(uint256(taskID)));

        ICustomTaskManager.LoadBalancer memory _loadBal;
        try ICustomTaskManager(TASK_MANAGER).S_loadBalancer() returns (ICustomTaskManager.LoadBalancer memory __loadBal)
        {
            _loadBal = __loadBal;
        } catch (bytes memory err) {
            emit Events.LoadBalancerLoadingError(err);

            // Indicates external need for fix
            return (combatant.isInCombat() && _isValidAddress(activeTask), activeTask);
        }

        uint64 activeBlock = uint64(_loadBal.activeBlockMedium);
        uint64 targetBlock = uint64(uint256(taskID) >> 160);

        if (!_isValidAddress(combatant.owner)) {
            combatant.owner = _loadOwner(combatant.id);
        }

        if (_isValidAddress(activeTask)) {
            if (activeBlock > targetBlock) {
                _clearActiveTask(combatant.id);
                if (combatant.owner == key.owner && key.expiration > 0) {
                    _updateSessionKey(activeTask, false, key.owner, 0);
                }
                activeTask = _EMPTY_ADDRESS;
            } else {
                SessionKey memory key = _loadSessionKey(activeTask);
                if (key.expiration <= block.number) {
                    _clearActiveTask(combatant.id);
                    if (combatant.owner == key.owner && key.expiration > 0) {
                        _updateSessionKey(activeTask, false, key.owner, 0);
                    }
                    activeTask = _EMPTY_ADDRESS;
                } else {
                    hasActiveCombatTask = true;
                }
            }
        }

        if (!combatant.isMonster()) {
            AbilityTracker memory activeAbility = _loadAbility(combatant.id);
            if (_isValidAddress(activeAbility.taskAddress)) {
                SessionKey memory key = _loadSessionKey(activeAbility.taskAddress);
                if (key.expiration <= block.number) {
                    _clearAbility(combatant.id);
                    if (combatant.owner == key.owner && key.expiration > 0) {
                        _updateSessionKey(activeAbility.taskAddress, false, key.owner, 0);
                    }
                } else if (activeBlock > activeAbility.targetBlock + 1) {
                    _clearAbility(combatant.id);
                    if (combatant.owner == key.owner && key.expiration > 0) {
                        _updateSessionKey(activeAbility.taskAddress, false, key.owner, 0);
                    }
                }
            }
        }
    }

    function areaCleanUp(uint8 depth, uint8 x, uint8 y) public {
        uint256 minGasRemaining = gasleft() > 800_000 ? 600_000 : 200_000;

        BattleArea memory area = _loadArea(depth, x, y);
        uint256 combinedBitmap = uint256(area.playerBitMap) | uint256(area.monsterBitMap);
        uint256 removalBitmap;

        // Can't have an index of 0, start i at 1.
        uint256 targetIndex = 1;

        while (gasleft() > minGasRemaining && combinedBitmap != 0 && targetIndex++ < 64) {
            uint256 indexBit = 1 << targetIndex;

            // If in combat, check if opponent exists
            if (combinedBitmap & indexBit != 0) {
                BattleNad memory combatant = _loadCombatant(depth, x, y, targetIndex);

                // CASE: combatant didnt load
                if (!_isValidID(combatant.id)) {
                    // This indicates a big issue / error with tracking - something is not
                    // being handled correctly asynchronously
                    combinedBitmap &= ~indexBit;
                    removalBitmap |= indexBit;

                    area.monsterBitMap = uint64(uint256(area.monsterBitMap) & ~indexBit);
                    area.playerBitMap = uint64(uint256(area.playerBitMap) & ~indexBit);
                    _clearCombatantArraySlot(depth, x, y, uint8(targetIndex));
                    area.update = true;

                    // CASE: combatant is dead
                } else if (combatant.isDead()) {
                    combinedBitmap &= ~indexBit;
                    removalBitmap |= indexBit;

                    if (_isDeadUnaware(combatant.id)) {
                        _setKiller(combatant.id, _SYSTEM_KILLER);
                        combatant = _exitCombat(combatant);

                        emit Events.PlayerDied(combatant.areaID(), combatant.id);
                    }

                    if (_isDeadUnprocessed(combatant.id)) {
                        (combatant, area) = _processDeathDuringDeceasedTurn(combatant, area);
                    } else {
                        area.monsterBitMap = uint64(uint256(area.monsterBitMap) & ~indexBit);
                        area.playerBitMap = uint64(uint256(area.playerBitMap) & ~indexBit);
                        _clearCombatantArraySlot(depth, x, y, uint8(targetIndex));
                        area.update = true;
                    }
                }
            }
        }

        minGasRemaining = gasleft() > 650_000 ? 450_000 : 50_000;

        if (combinedBitmap != 0 && removalBitmap != 0) {
            while (gasleft() > minGasRemaining && targetIndex++ < 64) {
                uint256 indexBit = 1 << targetIndex;

                // If in combat, check if opponent exists
                if (combinedBitmap & indexBit != 0) {
                    BattleNad memory combatant = _loadCombatant(depth, x, y, targetIndex);
                    uint256 combatantBitmap = uint256(combatant.stats.combatantBitMap);

                    if (combatantBitmap == 0) {
                        continue;
                    }

                    if (combatantBitmap & (~removalBitmap) != combatantBitmap) {
                        combatantBitmap &= ~removalBitmap;
                        combatant.tracker.updateStats = true;
                    }

                    if (combatantBitmap & combinedBitmap != combatantBitmap) {
                        combatantBitmap &= combinedBitmap;
                        combatant.tracker.updateStats = true;
                    }

                    if (combatantBitmap == 0) {
                        combatant = _exitCombat(combatant);
                    }
                    _storeBattleNad(combatant);
                }
            }
        }
        _storeArea(area, depth, x, y);
    }

    function _buildCombatTracker(BattleNad memory character)
        internal
        view
        returns (CombatTracker memory combatTracker)
    {
        bytes32 taskID = _loadActiveTaskID(character.id);
        if (!_isValidID(taskID)) {
            combatTracker.hasTaskError = character.isInCombat();
            combatTracker.taskAddress = _EMPTY_ADDRESS;
            return combatTracker;
        }

        address taskAddress = address(uint160(uint256(taskID)));
        uint64 targetBlock = uint64(uint256(taskID >> 160));

        if (!_isValidAddress(taskAddress)) {
            combatTracker.hasTaskError = character.isInCombat();
            combatTracker.taskAddress = _EMPTY_ADDRESS;
            return combatTracker;
        }

        ICustomTaskManager.LoadBalancer memory loadBal = ICustomTaskManager(TASK_MANAGER).S_loadBalancer();

        if (loadBal.activeBlockMedium > targetBlock) {
            combatTracker.hasTaskError = character.isInCombat();
            return combatTracker;
        } else {
            SessionKey memory key = _loadSessionKey(taskAddress);
            if (key.expiration <= block.number) {
                combatTracker.hasTaskError = true;
                return combatTracker;
            }
        }

        combatTracker.taskAddress = taskAddress;
        combatTracker.targetBlock = targetBlock;

        // NOTE: Active block can't pass current block
        uint256 executorDelay = block.number - loadBal.activeBlockMedium;
        combatTracker.executorDelay =
            executorDelay > MAX_ESTIMATED_EXECUTOR_DELAY ? MAX_ESTIMATED_EXECUTOR_DELAY_UINT8 : uint8(executorDelay);

        if (targetBlock > block.number) {
            combatTracker.pending = true;
            return combatTracker;
        }

        uint256 taskDelay = block.number - targetBlock;
        combatTracker.taskDelay =
            taskDelay > MAX_ESTIMATED_TASK_DELAY ? MAX_ESTIMATED_TASK_DELAY_UINT8 : uint8(taskDelay);

        return combatTracker;
    }

    // Overrides of the GeneralReschedulingTask
    // We're effectively setting BattleNads *as* the task implementation to save gas
    function GENERAL_TASK_IMPL() public view override returns (address) {
        return address(this);
    }

    function _matchCalldataHash(bytes memory data) internal view override returns (bool) {
        return matchCalldataHash(address(this), data);
    }

    function _setRescheduleData(
        address task,
        uint256 maxPayment,
        uint256 targetBlock,
        bool setOwnerAsMsgSenderDuringTask
    )
        internal
        override
    {
        setRescheduleData(task, maxPayment, targetBlock, setOwnerAsMsgSenderDuringTask);
    }

    function _targetSenderCheck() internal view override {
        if (address(this) != _loadTaskTarget()) {
            revert OnlyTargetCanSetReschedule();
        }
    }
}
