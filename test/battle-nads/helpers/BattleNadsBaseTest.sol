// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { BaseTest } from "test/BaseTest.sol";
import { ITaskManager } from "@fastlane-contracts/task-manager/interfaces/ITaskManager.sol";
import { BattleNadsWrapper } from "test/battle-nads/helpers/BattleNadsWrapper.sol";
// BattleNads Specific Imports (Copied from original test file)
import {
    BattleNad,
    BattleNadStats,
    BattleArea,
    StorageTracker,
    Inventory,
    DataFeed,
    Log,
    LogType,
    BattleNadLite,
    Ability,
    AbilityTracker,
    CharacterClass
} from "src/battle-nads/Types.sol";
import {
    SessionKey,
    SessionKeyData,
    GasAbstractionTracker
} from "lib/fastlane-contracts/src/common/relay/GasRelayTypes.sol";
import { BattleNadsEntrypoint } from "src/battle-nads/Entrypoint.sol";
import { StatSheet } from "src/battle-nads/libraries/StatSheet.sol";

// Base test contract
contract BattleNadsBaseTest is BaseTest {
    using StatSheet for BattleNad;
    using StatSheet for BattleNadLite;

    BattleNadsWrapper public battleNads;

    // Common Actors
    address public constant cranker = address(71);
    address public constant user1 = address(7);
    address public constant user2 = address(8);
    address public constant user3 = address(9);
    address public constant user4 = address(10); // Added for more tests

    // Common Session Keys
    address public constant userSessionKey1 = address(11);
    address public constant userSessionKey2 = address(22);
    address public constant userSessionKey3 = address(33);
    address public constant userSessionKey4 = address(44); // Added for more tests

    // Character IDs (to be assigned in specific test setups)
    bytes32 public character1;
    bytes32 public character2;
    bytes32 public character3;
    bytes32 public character4;

    uint256 public constant EXPECTED_ASCEND_DELAY = 200; //max delay for ascend task

    // Receive function for MON payments
    receive() external payable { }

    // Common Setup
    function setUp() public virtual override {
        super.setUp();

        vm.deal(cranker, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether); // Deal MON to new user

        battleNads = new BattleNadsWrapper(address(taskManager), address(shMonad));
    }

    /// @notice Advances blocks and executes tasks until target block is reached.
    function _rollForward(uint256 n) internal {
        uint256 currentBlock = block.number;
        uint256 targetBlock = block.number + n;
        uint256 jump = n == 1 ? 1 : 16;

        while (currentBlock < targetBlock) {
            vm.prank(cranker);
            uint256 feesEarned = taskManager.executeTasks(address(this), 0);
            if (feesEarned == 0) {
                vm.roll(currentBlock + jump);
                currentBlock = block.number;
            }
        }
        taskManager.executeTasks(address(this), 0);
    }

    /// @notice Checks balance shortfall for a character and tops up from owner if needed.
    function _topUpBonded(uint256 characterIndex) internal {
        bytes32 charId;
        address owner;

        if (characterIndex == 1) {
            charId = character1;
            owner = user1;
        } else if (characterIndex == 2) {
            charId = character2;
            owner = user2;
        } else if (characterIndex == 3) {
            charId = character3;
            owner = user3;
        } else if (characterIndex == 4) {
            charId = character4;
            owner = user4;
        } else {
            revert("Invalid character index for top-up");
        }

        if (charId == bytes32(0)) return; // Character not created yet

        uint256 shortfall = battleNads.shortfallToRecommendedBalanceInMON(charId);

        if (shortfall > 0) {
            vm.prank(owner);
            battleNads.replenishGasBalance{ value: shortfall }();
        }
    }

    /// @notice Convenience function to get full BattleNad struct by index.
    function _battleNad(uint256 index) internal view returns (BattleNad memory battleNad) {
        bytes32 charId;
        if (index == 1) {
            charId = character1;
        } else if (index == 2) {
            charId = character2;
        } else if (index == 3) {
            charId = character3;
        } else if (index == 4) {
            charId = character4;
        } else {
            // Allow fetching by direct ID if index > 4 (e.g., for monsters)
            battleNad = battleNads.getBattleNad(bytes32(index));
            return battleNad;
        }

        if (charId != bytes32(0)) {
            battleNad = battleNads.getBattleNad(charId);
        }
        // Returns empty struct if character ID is zero
    }

    /// @notice Helper function to get task ID from the most recent TaskScheduled event
    function _getLastScheduledTaskId(VmSafe.Log[] memory logs) internal pure returns (bytes32) {
        bytes32 eventSelector = keccak256("TaskScheduled(bytes32,address,uint64)");
        for (uint256 i = logs.length; i > 0; i--) {
            VmSafe.Log memory currentLog = logs[i - 1];
            if (currentLog.topics[0] == eventSelector) {
                // Ensure the task was scheduled by the battleNads contract (or its wrapper)
                // address scheduler = address(uint160(uint256(currentLog.topics[2]))); // topic[2] should be scheduler
                // if (scheduler == address(battleNads)) { // Need instance available or pass as arg
                return currentLog.topics[1]; // topic[1] is taskId
                    // }
            }
        }
        revert("No TaskScheduled event found"); // Or return bytes32(0);
    }

    /// @notice Helper to create a character and ensure the spawn task completes.
    function _createCharacterAndSpawn(
        uint256 userIndex, // 1, 2, 3, or 4
        string memory name,
        uint256 str,
        uint256 vit,
        uint256 dex,
        uint256 qui,
        uint256 stu,
        uint256 lck,
        address sessionKey,
        uint256 deadline
    )
        internal
        returns (bytes32 characterId)
    {
        address owner;
        if (userIndex == 1) owner = user1;
        else if (userIndex == 2) owner = user2;
        else if (userIndex == 3) owner = user3;
        else if (userIndex == 4) owner = user4;
        else revert("Invalid user index for character creation");

        uint256 creationCost = battleNads.estimateBuyInAmountInMON();
        vm.prank(owner);
        characterId =
            battleNads.createCharacter{ value: creationCost }(name, str, vit, dex, qui, stu, lck, sessionKey, deadline);

        // Assign to state variable
        if (userIndex == 1) character1 = characterId;
        else if (userIndex == 2) character2 = characterId;
        else if (userIndex == 3) character3 = characterId;
        else if (userIndex == 4) character4 = characterId;

        // Roll forward enough blocks to ensure the spawn task executes
        // Need a way to determine spawn delay or roll sufficiently far
        _waitForSpawn(characterId);

        return characterId;
    }

    // Helper to wait for spawn
    function _waitForSpawn(bytes32 charId) internal returns (BattleNad memory nad) {
        bool spawned = false;
        for (uint256 i = 0; i < 20; ++i) {
            nad = battleNads.getBattleNad(charId);
            if (nad.stats.x != 0 || nad.stats.y != 0) {
                spawned = true;
                break;
            }
            _rollForward(1);
        }
        require(spawned, "Helper: Character did not spawn within timeout");
        return nad;
    }

    /// @notice Helper function to trigger random combat through movement
    /// This is the only time movement should be used - to START combat, not progress it
    function _triggerRandomCombat(bytes32 charId) internal returns (bool success) {
        BattleNad memory nad = battleNads.getBattleNad(charId);
        require(nad.id != bytes32(0), "Character must exist");
        require(nad.stats.index > 0, "Character must be spawned");

        // Try movement to trigger random monster encounters
        for (uint256 i = 0; i < 20; ++i) {
            vm.prank(userSessionKey1);
            if (i % 4 == 0) battleNads.moveNorth(charId);
            else if (i % 4 == 1) battleNads.moveEast(charId);
            else if (i % 4 == 2) battleNads.moveSouth(charId);
            else battleNads.moveWest(charId);

            _rollForward(1);
            BattleNad memory updatedNad = battleNads.getBattleNad(charId);
            if (updatedNad.stats.combatants > 0) {
                return true;
            }
        }

        return false;
    }

    /// @notice Helper to progress combat using abilities (the correct way)
    /// @param charId Character in combat
    /// @param maxRounds Maximum number of ability rounds to attempt
    /// @return survived Whether character survived combat
    /// @return finalState Final character state
    function _fightWithAbilities(
        bytes32 charId,
        uint256 maxRounds
    )
        internal
        returns (bool survived, BattleNad memory finalState)
    {
        BattleNad memory currentState = battleNads.getBattleNad(charId);
        require(currentState.stats.combatants > 0, "Character must be in combat");

        uint256 lastAbilityBlock = 0; // Track when last ability was used

        for (uint256 i = 0; i < maxRounds; i++) {
            currentState = battleNads.getBattleNad(charId);

            // Check if combat is over
            if (currentState.stats.combatants == 0) {
                return (currentState.stats.health > 0, currentState);
            }

            // Check if there's an active ability task that needs to execute
            if (currentState.activeAbility.taskAddress != address(0)) {
                uint256 targetBlock = uint256(currentState.activeAbility.targetBlock);
                if (targetBlock > block.number) {
                    // Roll forward to execute the ability task
                    uint256 blocksToRoll = targetBlock - block.number + 1;
                    _rollForward(blocksToRoll);

                    // Track when this ability executed for cooldown calculation
                    lastAbilityBlock = block.number;

                    // Check if combat ended after ability execution
                    BattleNad memory afterExecution = battleNads.getBattleNad(charId);
                    if (afterExecution.stats.combatants == 0) {
                        return (afterExecution.stats.health > 0, afterExecution);
                    }
                    continue; // Check for next ability or combat end
                }
            }

            // Check if we need to wait for ability cooldown (200 blocks)
            if (lastAbilityBlock > 0 && block.number < lastAbilityBlock + 200) {
                uint256 cooldownRemaining = (lastAbilityBlock + 200) - block.number;
                vm.roll(block.number + cooldownRemaining + 1);
            }

            // Use appropriate ability to progress combat
            bool abilityUsed = _useAppropriateAbility(charId);

            if (abilityUsed) {
                // Ability was scheduled, will be handled in next iteration
                lastAbilityBlock = block.number; // Update ability usage time
                continue;
            } else {
                // If we can't use abilities, wait a bit for combat to progress naturally
                _rollForward(10);
            }
        }

        // If we get here, combat didn't end in maxRounds
        BattleNad memory timeoutState = battleNads.getBattleNad(charId);
        return (timeoutState.stats.health > 0, timeoutState);
    }

    /// @notice Helper to find a combat target for the character
    /// @param charId Character in combat
    /// @return targetIndex Index of a combatant to target (0 if none found)
    function _findCombatTarget(bytes32 charId) internal view returns (uint256 targetIndex) {
        try battleNads.testGetCombatantIDs(charId) returns (bytes32[] memory combatantIDs, uint256 numberOfCombatants) {
            if (numberOfCombatants > 0) {
                // Get the first combatant's stats to find their index
                BattleNad memory firstCombatant = battleNads.getBattleNad(combatantIDs[0]);
                return uint256(firstCombatant.stats.index);
            }
        } catch {
            // Fallback: return nextTargetIndex if available
            BattleNad memory character = battleNads.getBattleNad(charId);
            if (character.stats.nextTargetIndex != 0) {
                return uint256(character.stats.nextTargetIndex);
            }
            return 1; // Last resort fallback
        }
        return 0;
    }

    /// @notice Helper to determine which ability to use based on character class and combat state
    /// @param charId Character to get ability for
    /// @return abilityIndex Ability index to use (1 or 2)
    /// @return needsTarget Whether this ability needs a target
    function _getOptimalAbility(bytes32 charId) internal view returns (uint256 abilityIndex, bool needsTarget) {
        BattleNad memory character = battleNads.getBattleNad(charId);
        CharacterClass class = character.stats.class;

        // Determine optimal ability based on class
        if (class == CharacterClass.Bard) {
            // Use DoDance (offensive) if in combat
            return (2, true);
        } else if (class == CharacterClass.Warrior) {
            // Use ShieldBash (offensive) if in combat
            return (1, true);
        } else if (class == CharacterClass.Rogue) {
            // Use ApplyPoison (offensive) if in combat
            return (2, true);
        } else if (class == CharacterClass.Monk) {
            // Use Smite (offensive) if in combat
            return (2, true);
        } else if (class == CharacterClass.Sorcerer) {
            // Use Fireball (offensive) if in combat
            return (2, true);
        } else {
            // Fallback to first ability
            return (1, false);
        }
    }

    /// @notice Helper to use the most appropriate ability for the character's class and situation
    /// @param charId Character using ability
    /// @return success Whether ability was successfully used
    function _useAppropriateAbility(bytes32 charId) internal returns (bool success) {
        BattleNad memory character = battleNads.getBattleNad(charId);

        // Don't use ability if one is already active
        if (character.activeAbility.taskAddress != address(0) && character.activeAbility.taskAddress != address(1)) {
            return false;
        }

        // Get the optimal ability for this character's class
        (uint256 abilityIndex, bool needsTarget) = _getOptimalAbility(charId);

        uint256 targetIndex = 0;
        if (needsTarget) {
            targetIndex = _findCombatTarget(charId);
            if (targetIndex == 0) {
                // No target found, can't use offensive ability
                return false;
            }
        }

        // Use the ability
        vm.prank(userSessionKey1);
        try battleNads.useAbility(charId, targetIndex, abilityIndex) {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Helper to get character class name for debugging
    /// @param class Character class enum
    /// @return className String representation of class
    function _getClassName(CharacterClass class) internal pure returns (string memory className) {
        if (class == CharacterClass.Bard) return "Bard";
        if (class == CharacterClass.Warrior) return "Warrior";
        if (class == CharacterClass.Rogue) return "Rogue";
        if (class == CharacterClass.Monk) return "Monk";
        if (class == CharacterClass.Sorcerer) return "Sorcerer";
        if (class == CharacterClass.Basic) return "Basic Monster";
        if (class == CharacterClass.Elite) return "Elite Monster";
        if (class == CharacterClass.Boss) return "Boss Monster";
        return "Unknown";
    }

    /// @notice Helper to observe combat progress through logs
    /// @param owner Owner address to get logs for
    /// @return combatLogs Array of combat-related logs since last check
    function _getCombatLogs(address owner) internal returns (Log[] memory combatLogs) {
        DataFeed[] memory dataFeeds = battleNads.printLogs(owner);

        // Count combat logs
        uint256 combatLogCount = 0;
        for (uint256 i = 0; i < dataFeeds.length; i++) {
            for (uint256 j = 0; j < dataFeeds[i].logs.length; j++) {
                Log memory logEntry = dataFeeds[i].logs[j];
                if (
                    logEntry.logType == LogType.Combat || logEntry.logType == LogType.Ability
                        || logEntry.logType == LogType.InstigatedCombat
                ) {
                    combatLogCount++;
                }
            }
        }

        // Extract combat logs
        combatLogs = new Log[](combatLogCount);
        uint256 index = 0;
        for (uint256 i = 0; i < dataFeeds.length; i++) {
            for (uint256 j = 0; j < dataFeeds[i].logs.length; j++) {
                Log memory logEntry = dataFeeds[i].logs[j];
                if (
                    logEntry.logType == LogType.Combat || logEntry.logType == LogType.Ability
                        || logEntry.logType == LogType.InstigatedCombat
                ) {
                    combatLogs[index] = logEntry;
                    index++;
                }
            }
        }

        return combatLogs;
    }

    /// @notice Helper to modify character stats using vm.store (moved from combat test)
    function _modifyCharacterStat(bytes32 charId, string memory statName, uint256 value) internal {
        uint256 slot = 3; // Storage slot for characterStats mapping
        bytes32 statSlot = keccak256(abi.encode(charId, slot));
        uint256 packedData = uint256(vm.load(address(battleNads), statSlot));

        // Define offsets for different stats (based on BattleNadStats struct)
        uint256 offset;
        uint256 mask;

        if (keccak256(bytes(statName)) == keccak256("combatantBitMap")) {
            offset = 0;
            mask = uint256(type(uint64).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("combatants")) {
            offset = 72;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("sumOfCombatantLevels")) {
            offset = 80;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("health")) {
            offset = 88;
            mask = uint256(type(uint16).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("weaponID")) {
            offset = 112;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("armorID")) {
            offset = 104;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("sturdiness")) {
            offset = 160;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("dexterity")) {
            offset = 176;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("vitality")) {
            offset = 184;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("strength")) {
            offset = 192;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("level")) {
            offset = 224;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("class")) {
            offset = 248;
            mask = uint256(type(uint8).max) << offset;
        } else if (keccak256(bytes(statName)) == keccak256("unspentAttributePoints")) {
            offset = 216;
            mask = uint256(type(uint8).max) << offset;
        } else {
            revert(string.concat("Unknown stat: ", statName));
        }

        // Clear old value and set new value
        packedData &= (~mask);
        packedData |= (value << offset);

        vm.store(address(battleNads), statSlot, bytes32(packedData));
    }

    /// @notice Helper to use an ability and execute it, handling cooldowns properly
    /// @param charId Character using ability
    /// @param targetIndex Target index for targeted abilities
    /// @param abilityIndex Ability index to use
    /// @return success Whether ability was successfully used and executed
    function _useAbilityAndExecute(
        bytes32 charId,
        uint256 targetIndex,
        uint256 abilityIndex
    )
        internal
        returns (bool success)
    {
        BattleNad memory before = battleNads.getBattleNad(charId);

        // Use ability
        vm.prank(userSessionKey1);
        try battleNads.useAbility(charId, targetIndex, abilityIndex) {
            BattleNad memory afterAbility = battleNads.getBattleNad(charId);

            // If ability was scheduled as task, wait for it to execute
            if (afterAbility.activeAbility.taskAddress != address(0)) {
                uint256 targetBlock = uint256(afterAbility.activeAbility.targetBlock);
                if (targetBlock > block.number) {
                    _rollForward(targetBlock - block.number + 1);
                }

                // Skip ahead for cooldown (200 blocks as per _checkAbilityTimeout)
                vm.roll(block.number + 200);
            }

            BattleNad memory finalState = battleNads.getBattleNad(charId);

            // Check if ability had some effect
            return (
                finalState.stats.combatants != before.stats.combatants
                    || finalState.stats.combatantBitMap != before.stats.combatantBitMap
                    || finalState.stats.health != before.stats.health || finalState.activeAbility.taskAddress == address(0)
                    || finalState.activeAbility.taskAddress == address(1)
            );
        } catch {
            return false;
        }
    }

    /// @notice Helper to use a targeted ability in combat
    /// @param charId Character using ability
    /// @param abilityIndex Ability index (should be offensive ability like 2 for most classes)
    /// @return success Whether targeted ability was used successfully
    function _useTargetedAbility(bytes32 charId, uint256 abilityIndex) internal returns (bool success) {
        uint256 targetIndex = _findCombatTarget(charId);
        if (targetIndex == 0) {
            return false; // No target available
        }

        return _useAbilityAndExecute(charId, targetIndex, abilityIndex);
    }

    /// @notice Helper to use a non-targeted ability
    /// @param charId Character using ability
    /// @param abilityIndex Ability index (should be non-offensive ability like 1 for most classes)
    /// @return success Whether non-targeted ability was used successfully
    function _useNonTargetedAbility(bytes32 charId, uint256 abilityIndex) internal returns (bool success) {
        return _useAbilityAndExecute(charId, 0, abilityIndex);
    }
}
