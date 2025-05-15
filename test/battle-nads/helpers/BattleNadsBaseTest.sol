// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";
import { ITaskManager } from "@fastlane-task-manager/src/interfaces/ITaskManager.sol";
// BattleNads Specific Imports (Copied from original test file)
import {
    BattleNad,
    BattleNadStats,
    BattleInstance,
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
import { SessionKey, SessionKeyData, GasAbstractionTracker } from "src/battle-nads/cashier/CashierTypes.sol";
import { BattleNadsEntrypoint } from "src/battle-nads/Entrypoint.sol";
import { BattleNadsImplementation } from "src/battle-nads/tasks/BattleNadsImplementation.sol";
import { StatSheet } from "src/battle-nads/libraries/StatSheet.sol";

// Wrapper contract for easier testing interactions
contract BattleNadsWrapper is BattleNadsEntrypoint {
    using StatSheet for BattleNad;
    using StatSheet for BattleNadLite;

    uint256 public immutable START_BLOCK;
    mapping(address => uint256) public lastBlocks;

    constructor(address taskManager, address shMonad) BattleNadsEntrypoint(taskManager, shMonad) {
        START_BLOCK = block.number;
    }

    // --- Wrapper Helper Functions (Copied from original test file) ---

    function getLiteCombatants(address owner) public view returns (BattleNadLite[] memory liteCombatants) {
        (,,, liteCombatants,,,,,,,,,) = pollForFrontendData(owner, block.number - 1);
    }

    function getCombatantBattleNads(address owner) public view returns (BattleNad[] memory combatants) {
        BattleNadLite[] memory liteCombatants = getLiteCombatants(owner);
        combatants = new BattleNad[](liteCombatants.length);
        for (uint256 i; i < liteCombatants.length; i++) {
            bytes32 combatantID = liteCombatants[i].id;
            combatants[i] = getBattleNad(combatantID);
        }
        return combatants;
    }

    function printLogs(address owner) public returns (DataFeed[] memory dataFeeds) {
        uint256 startBlock = lastBlocks[owner];
        if (startBlock < START_BLOCK) {
            startBlock = START_BLOCK;
        }
        dataFeeds = getDataFeed(owner, startBlock, block.number);
        lastBlocks[owner] = block.number;

        for (uint256 i = 0; i < dataFeeds.length; i++) {
            DataFeed memory dataFeed = dataFeeds[i];
            if (dataFeed.logs.length > 0) {
                console.log("\nBlock Number:", dataFeed.blockNumber);
                for (uint256 j = 0; j < dataFeed.logs.length; j++) {
                    Log memory logEntry = dataFeed.logs[j];
                    if (logEntry.logType == LogType.Combat) {
                        // Broke down into multiple calls (<= 4 args each)
                        console.log("  Combat:", logEntry.mainPlayerIndex, "->", logEntry.otherPlayerIndex);
                        console.log("    Dmg:", logEntry.damageDone, "Heal:", logEntry.healthHealed);
                        console.log("    Died:", logEntry.targetDied);
                    } else if (logEntry.logType == LogType.InstigatedCombat) {
                        console.log("  InitiateCombat:", logEntry.mainPlayerIndex, "->", logEntry.otherPlayerIndex);
                    } else if (logEntry.logType == LogType.EnteredArea) {
                        console.log("  EnteredArea:", logEntry.mainPlayerIndex);
                    } else if (logEntry.logType == LogType.LeftArea) {
                        console.log("  LeftArea:", logEntry.mainPlayerIndex);
                    } else if (logEntry.logType == LogType.Ability) {
                        // Broke down into multiple calls (<= 4 args each)
                        console.log(
                            "  Ability:", logEntry.mainPlayerIndex, "Type:", uint8(Ability(logEntry.lootedWeaponID))
                        );
                        console.log("    Stage:", logEntry.lootedArmorID, "Dmg:", logEntry.damageDone);
                        console.log("    Heal:", logEntry.healthHealed);
                    } else if (logEntry.logType == LogType.Ascend) {
                        console.log("  Ascend:", logEntry.mainPlayerIndex, "Value:", logEntry.value);
                    }
                }
            }
        }
        return dataFeeds;
    }

    function printBattleNad(BattleNad memory battleNad) public pure {
        console.log("");
        console.log("BattleNad: ", battleNad.name, "id:", uint256(battleNad.id)); // 4 args - OK
        console.log("  Owner:", battleNad.owner); // 2 args - OK
        console.log("  Class:", uint8(battleNad.stats.class)); // 2 args - OK
        // Broke down location log
        console.log("  Location (d,x,y,i):", battleNad.stats.depth, battleNad.stats.x);
        console.log("    ", battleNad.stats.y, battleNad.stats.index);
        // Broke down stats log
        console.log(
            "  Stats (lvl,hp,str,vit):", battleNad.stats.level, battleNad.stats.health, battleNad.stats.strength
        );
        console.log(
            "     (vit,dex,qui,stu):", battleNad.stats.vitality, battleNad.stats.dexterity, battleNad.stats.quickness
        );
        console.log("     (stu,lck):", battleNad.stats.sturdiness, battleNad.stats.luck);
        // Broke down combat log
        console.log("  Combat (tgts,sumLvl):", battleNad.stats.combatants, battleNad.stats.sumOfCombatantLevels);
        console.log("     (map,next):", battleNad.stats.combatantBitMap, battleNad.stats.nextTargetIndex);
        // Broke down equip log (was already ok, but for consistency)
        console.log("  Equip (wep,arm):", battleNad.stats.weaponID, battleNad.stats.armorID); // 4 args - OK
        console.log("  Task:", battleNad.activeTask); // 2 args - OK
        console.log("  Balance:", battleNad.inventory.balance); // 2 args - OK
    }
}

// Base test contract
contract BattleNadsBaseTest is Test {
    using StatSheet for BattleNad;
    using StatSheet for BattleNadLite;

    BattleNadsWrapper public battleNads;
    ITaskManager public immutable taskManager = ITaskManager(0x5277C4c882BA9425E6615955b17Af34030432f27);
    address public immutable shMonad = address(0x3a98250F98Dd388C211206983453837C8365BDc1);

    // Common Actors
    address public constant cranker = address(71);
    address public constant user1 = address(1);
    address public constant user2 = address(2);
    address public constant user3 = address(3);
    address public constant user4 = address(4); // Added for more tests

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

    // Receive function for ETH payments
    receive() external payable { }

    // Common Setup
    function setUp() public virtual {
        vm.deal(cranker, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(user4, 100 ether); // Deal ETH to new user

        battleNads = new BattleNadsWrapper(address(taskManager), address(shMonad));
    }

    // --- Common Helper Functions (Copied/Adapted from original test file) ---

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
}
