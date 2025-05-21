//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { IShMonad } from "../interfaces/shmonad/IShMonad.sol";
import { ITaskManager } from "@fastlane-task-manager/src/interfaces/ITaskManager.sol";
import { IBattleNadsImplementation } from "./interfaces/IBattleNadsImplementation.sol";

import { BattleNad, BattleNadStats, Inventory, Weapon, Armor, StorageTracker } from "./Types.sol";
import { Handler } from "./Handler.sol";
import { Names } from "./libraries/Names.sol";
import { Errors } from "./libraries/Errors.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

import { BattleNadsImplementation } from "./tasks/BattleNadsImplementation.sol";

// These are the entrypoint functions called by the tasks
contract TaskHandler is Handler {
    using StatSheet for BattleNad;
    using Names for BattleNad;

    address public immutable TASK_IMPLEMENTATION;

    constructor(address taskManager, address shMonad) Handler(taskManager, shMonad) {
        // Build task implementation
        BattleNadsImplementation taskImplementation = new BattleNadsImplementation();
        TASK_IMPLEMENTATION = address(taskImplementation);
    }

    // Called by a task
    function processTurn(bytes32 characterID)
        external
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment)
    {
        // Load character
        BattleNad memory attacker = _loadBattleNad(characterID);
        _validateCalledByTask(attacker);

        // Handle turn
        uint256 targetBlock;
        (attacker, reschedule, targetBlock) = _handleCombatTurn(attacker);

        // Set reschedule lock for reimbursement call afterwards
        if (reschedule) {
            // Calculate the maximum payment
            (reschedule, nextBlock, maxPayment) = _rescheduleTaskAccounting(attacker.owner, targetBlock);

            // Force kill the character if they can't maintain their task.
            if (!reschedule || nextBlock == 0) {
                _forceKill(attacker);
                return (false, 0, 0);
            }
        }

        // Store the data
        _storeBattleNad(attacker);

        // Rescheduling is handled by the task based on the return value of the function call.
        return (reschedule, nextBlock, maxPayment);
    }

    // Called by a task
    function processSpawn(bytes32 characterID)
        external
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment)
    {
        // Load character
        BattleNad memory attacker = _loadBattleNad(characterID);
        _validateCalledByTask(attacker);

        // Handle spawn
        uint256 targetBlock;
        (attacker, reschedule, targetBlock) = _handleSpawn(attacker);

        // Reschedule if necessary
        if (reschedule) {
            // Calculate the maximum payment and estimate
            // Calculate the maximum payment
            (reschedule, nextBlock, maxPayment) = _rescheduleTaskAccounting(attacker.owner, targetBlock);

            // Force kill the character if they can't maintain their task.
            if (!reschedule || nextBlock == 0) {
                _forceKill(attacker);
                return (false, 0, 0);
            }
        }

        // If successful, store the data
        attacker = _setActiveTask(attacker, address(0));
        _storeBattleNad(attacker);
        return (reschedule, nextBlock, maxPayment);
    }

    function processAscend(bytes32 characterID) external {
        address approvedTask = characterTasks[characterID];
        require(msg.sender == approvedTask, "ERR - UNAPPROVED CALLER");

        BattleNad memory player = _loadBattleNad(characterID);

        // Verify that the nad is still alive and not in combat
        if (player.isDead()) {
            player = _processAttackerDeath(player);
            player = _setActiveTask(player, address(0));
            _storeBattleNad(player);
            return;
        } else if (player.isInCombat()) {
            player = _setActiveTask(player, address(0));
            _storeBattleNad(player);
            return;
        }

        address owner = owners[characterID];

        uint256 cashedOutShMONShares = _forceKill(player);
        _logAscend(player, cashedOutShMONShares);

        if (owner != address(0)) {
            SafeTransferLib.safeTransfer(SHMONAD, owner, cashedOutShMONShares);
        }
    }

    // Called by a task
    function processAbility(bytes32 characterID)
        external
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment)
    {
        // Load character
        BattleNad memory attacker = _loadBattleNad(characterID);
        attacker.activeAbility = _loadAbility(attacker.id);

        _validateCalledByAbilityTask(attacker);

        // Handle spawn
        uint256 targetBlock;
        (attacker, reschedule, targetBlock) = _handleAbility(attacker);

        // Reschedule if necessary
        if (reschedule) {
            // Calculate the maximum payment
            (reschedule, nextBlock, maxPayment) = _rescheduleTaskAccounting(attacker.owner, targetBlock);

            // Force kill the character if they can't maintain their task.
            if (!reschedule || nextBlock == 0) {
                _forceKill(attacker);
                return (false, 0, 0);
            }
        }

        // If successful, store the data
        _storeBattleNad(attacker);
        return (reschedule, nextBlock, maxPayment);
    }

    function _createCombatTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        override
        returns (BattleNad memory, bool success)
    {
        if (combatant.owner == address(0)) {
            revert Errors.CharacterNotOwned(combatant.id);
        }

        // Get max task payment
        uint256 maxPayment = _amountBondedToThis(combatant.owner) / 2;

        // Calculate the maximum payment
        bytes memory data = abi.encodeCall(IBattleNadsImplementation.execute, (combatant.id));

        // Create the task
        bytes32 taskID;
        (success, taskID, targetBlock,) = _createTaskCustom(
            combatant.owner,
            maxPayment,
            MIN_REMAINDER_GAS,
            targetBlock,
            targetBlock + 65,
            TASK_IMPLEMENTATION,
            TASK_GAS,
            data
        );

        if (success) {
            // Get the task address, flag for storage in the future
            address taskAddress = address(uint160(uint256(taskID)));
            combatant = _setActiveTask(combatant, taskAddress);
        }

        // Return combatant
        return (combatant, success);
    }

    function _createSpawnTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        override
        returns (BattleNad memory, bool success)
    {
        if (combatant.owner == address(0)) {
            revert Errors.CharacterNotOwned(combatant.id);
        }

        // Get max task payment
        uint256 maxPayment = _amountBondedToThis(combatant.owner) / 2;

        // Calculate the maximum payment
        bytes memory data = abi.encodeCall(IBattleNadsImplementation.spawn, (combatant.id));

        // Create the task
        bytes32 taskID;
        (success, taskID, targetBlock,) = _createTaskCustom(
            combatant.owner,
            maxPayment,
            MIN_REMAINDER_GAS,
            targetBlock,
            targetBlock + 65,
            TASK_IMPLEMENTATION,
            TASK_GAS,
            data
        );

        if (success) {
            // Get the task address, flag for storage in the future
            address taskAddress = address(uint160(uint256(taskID)));
            combatant = _setActiveTask(combatant, taskAddress);
        }

        // Return combatant
        return (combatant, success);
    }

    function _createAbilityTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        override
        returns (BattleNad memory, bool success)
    {
        if (combatant.owner == address(0)) {
            revert Errors.CharacterNotOwned(combatant.id);
        }

        // Get max task payment
        uint256 maxPayment = _amountBondedToThis(combatant.owner);

        // Encode data
        bytes memory data = abi.encodeCall(IBattleNadsImplementation.ability, (combatant.id));

        // Create the task
        bytes32 taskID;
        (success, taskID, targetBlock,) = _createTaskCustom(
            combatant.owner,
            maxPayment,
            MIN_REMAINDER_GAS,
            targetBlock,
            targetBlock + 65,
            TASK_IMPLEMENTATION,
            TASK_GAS,
            data
        );

        if (success) {
            // Get the task address, flag for storage in the future
            combatant.activeAbility.taskAddress = address(uint160(uint256(taskID)));
            combatant.activeAbility.targetBlock = uint64(targetBlock);
            combatant.tracker.updateActiveAbility = true;
        }

        // Return combatant
        return (combatant, success);
    }

    function _createAscendTask(BattleNad memory combatant) internal override returns (BattleNad memory) {
        // Get max task payment
        uint256 maxPayment = _amountBondedToThis(combatant.owner);

        if (maxPayment == 0) return combatant;

        bytes memory data = abi.encodeCall(IBattleNadsImplementation.ascend, (combatant.id));

        // Create the task
        (bool success, bytes32 taskID,,) = _createTaskCustom(
            combatant.owner,
            maxPayment,
            MIN_REMAINDER_GAS,
            block.number + 96,
            block.number + 192,
            TASK_IMPLEMENTATION,
            TASK_GAS,
            data
        );

        if (success) {
            // Get the task address, flag for storage in the future
            address taskAddress = address(uint160(uint256(taskID)));
            combatant = _setActiveTask(combatant, taskAddress);
        } else {
            revert Errors.TaskNotScheduled();
        }
        return combatant;
    }

    function _validateCalledByTask(BattleNad memory combatant) internal view {
        if (combatant.activeTask != msg.sender) {
            revert Errors.InvalidCaller(msg.sender);
        }
    }

    function _validateCalledByAbilityTask(BattleNad memory combatant) internal view {
        if (combatant.activeAbility.taskAddress != msg.sender) {
            revert Errors.InvalidCaller(msg.sender);
        }
    }

    function _createTaskCustom(
        address payor,
        uint256 maxPayment, // In shares
        uint256 minExecutionGasRemaining,
        uint256 targetBlock,
        uint256 highestAcceptableBlock,
        address taskImplementation,
        uint256 taskGas,
        bytes memory taskData
    )
        internal
        returns (bool success, bytes32 taskID, uint256 blockNumber, uint256 amountPaid)
    {
        // Calculate the payment
        uint256 amountEstimated;

        if (maxPayment == 0) {
            return (success, taskID, blockNumber, amountPaid);
        }

        // Monitor gas carefully while searching for a cheap block.
        uint256 searchGas = gasleft();
        // TODO: update task schedule gas cost (150_000 is rough estimate)
        if (searchGas < minExecutionGasRemaining + 191_000) {
            return (success, taskID, blockNumber, amountPaid);
        }
        searchGas -= (minExecutionGasRemaining + 190_000);

        (amountEstimated, targetBlock) =
            _getNextAffordableBlock(maxPayment, targetBlock, highestAcceptableBlock, taskGas, searchGas);

        if (targetBlock == 0 || amountEstimated > maxPayment) {
            return (success, taskID, blockNumber, amountPaid);
        }

        // Take the estimated amount from the payor and then bond it to task manager
        // If payor is address(this) then the shares aren't bonded
        if (payor == address(this)) {
            _bondSharesToTaskManager(_convertMonToShMon(amountEstimated));
        } else {
            _takeFromOwnerBondedAmountInUnderlying(payor, amountEstimated);
            _bondAmountToTaskManager(amountEstimated);
        }

        // Reset the gas limits
        searchGas = gasleft();
        if (searchGas < 151_000 + minExecutionGasRemaining) {
            return (success, taskID, blockNumber, amountPaid);
        }
        searchGas -= (minExecutionGasRemaining + 150_000);

        // Schedule the task
        bytes memory returndata;
        (success, returndata) = TASK_MANAGER.call{ gas: searchGas }(
            abi.encodeCall(
                ITaskManager.scheduleWithBond,
                (taskImplementation, taskGas, uint64(targetBlock), amountEstimated, taskData)
            )
        );

        // Validate and decode
        if (success) {
            (success, amountPaid, taskID) = abi.decode(returndata, (bool, uint256, bytes32));
        }

        // Return result
        return (success, taskID, targetBlock, amountPaid);
    }

    function _rescheduleTaskAccounting(
        address payor,
        uint256 targetBlock
    )
        internal
        returns (bool success, uint256 nextBlock, uint256 amountEstimated)
    {
        // Calculate the maximum payment
        uint256 maxPayment = _amountBondedToThis(payor);
        if (maxPayment == 0) {
            return (false, 0, 0);
        }

        uint256 gasToUse = gasleft() / 2;
        if (gasToUse > 100_000) gasToUse = 100_000;

        (amountEstimated, nextBlock) =
            _getNextAffordableBlock(maxPayment, targetBlock, targetBlock + 65, TASK_GAS, gasToUse);
        if (nextBlock == 0 || amountEstimated > maxPayment) {
            return (false, 0, 0);
        }

        // Handle payment
        _takeFromOwnerBondedAmountInUnderlying(payor, amountEstimated);
        _bondAmountToTaskManager(amountEstimated);

        return (true, nextBlock, amountEstimated);
    }
}
