// SPDX-License-Identifier: MIT	
pragma solidity ^0.8.19;	
	
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";
import { VmSafe } from "forge-std/Vm.sol";

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

import {	
    SessionKey,	
    SessionKeyData,	
    GasAbstractionTracker	
} from "src/battle-nads/cashier/CashierTypes.sol";	

import { BattleNadsEntrypoint } from "src/battle-nads/Entrypoint.sol";	
import { BattleNadsImplementation } from "src/battle-nads/tasks/BattleNadsImplementation.sol";	

import { StatSheet } from "../../src/battle-nads/libraries/StatSheet.sol";	

import {console} from "forge-std/console.sol";	

contract BattleNadsWrapper is BattleNadsEntrypoint {	
    using StatSheet for BattleNad;	
    using StatSheet for BattleNadLite;	

    uint256 public immutable START_BLOCK;	

    mapping(address => uint256) public lastBlocks;	

    constructor(address taskManager, address shMonad) BattleNadsEntrypoint(taskManager, shMonad) { 	
        START_BLOCK = block.number;	
    }	

    function getLiteCombatants(address owner) public view returns (BattleNadLite[] memory liteCombatants) {	
        (,,,liteCombatants,,,,,,,,,) = pollForFrontendData(owner, block.number - 1);	
    }	

    function getCombatantBattleNads(address owner) public view returns (BattleNad[] memory combatants) {	
        BattleNadLite[] memory liteCombatants = getLiteCombatants(owner);	
        combatants = new BattleNad[](liteCombatants.length);	
        for (uint256 i; i<liteCombatants.length; i++) {	
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
                console.log(""); 	
                console.log("Block Number:", dataFeed.blockNumber);	

                for (uint256 j = 0; j < dataFeed.logs.length; j++) {	

                    Log memory log = dataFeed.logs[j];	

                    if (log.logType == LogType.Chat) { 	
                        // Print chat logs later	
                        continue;	

                    } else if (log.logType == LogType.Combat) {	
                        console.log("Combat Log");  	
                        console.log("Attacking Player Index:", log.mainPlayerIndex);	
                        console.log("Defending Player Index:", log.otherPlayerIndex);	
                        if (log.hit) {	
                            console.log("Hit");	
                        } else {	
                            console.log("Miss");	
                        }	
                        if (log.critical) {	
                            console.log("Critical");	
                        } else {	
                            console.log("Not Critical");	
                        }	
                        console.log("Damage Done:", log.damageDone);	
                        console.log("Health Healed:", log.healthHealed);	
                        if (log.targetDied) {	
                            console.log("Target Died");	
                        } else {	
                            console.log("Target Still Alive");	
                        }	
                        console.log("Value Received:", log.value);	
                        console.log("Experience Gained:", log.experience);	
                        console.log("Looted Weapon ID:", log.lootedWeaponID);	
                        console.log("Looted Armor ID:", log.lootedArmorID);	
                        console.log("");	

                    } else if (log.logType == LogType.InstigatedCombat) {	
                        console.log("Instigated Combat Log");	
                        console.log("Attacker Index:", log.mainPlayerIndex);	
                        console.log("Defender Index:", log.otherPlayerIndex);	
                        console.log("");	

                    } else if (log.logType == LogType.EnteredArea) {	
                        console.log("Entered Area Log");	
                        console.log("");	

                    } else if (log.logType == LogType.LeftArea) {	
                        console.log("Left Area Log");	
                        console.log("");	

                    } else if (log.logType == LogType.Ascend) {	
                        console.log("Ascend Log");	
                        console.log("Value Received:", log.value);	
                        console.log("");	

                    } else if (log.logType == LogType.Ability) {	
                        console.log("Ability Log");	
                        console.log("Ability Type:", log.lootedWeaponID);	
                        console.log("Ability Stage:", log.lootedArmorID);	
                        console.log("Damage Done:", log.damageDone);	
                        console.log("Health Healed:", log.healthHealed);	
                        console.log("");	
                    }	
                }	
            }	
        }	
    }	

    function printBattleNad(BattleNad memory battleNad) public view {	
        console.log("");	
        console.log("Block Number:", block.number);	
        printBattleNadAttributes(battleNad);	
        printBattleNadLocation(battleNad);	
        printBattleNadStats(battleNad);	
        printBattleNadCombat(battleNad);	
        printBattleNadHandling(battleNad);	
        console.log("");	
    }	

    function printBattleNadShort(BattleNad memory battleNad) public view {	
        console.log("");	
        console.log("Block Number:", block.number);	
        printBattleNadLocation(battleNad);	
        printBattleNadCombat(battleNad);	
        console.log("");	
    }	

    function printBattleNadLocation(BattleNad memory battleNad) public pure {	
        console.log("======= Location =======");	
        console.log(" d:", uint256(battleNad.stats.depth));	
        console.log(" x:", uint256(battleNad.stats.x));	
        console.log(" y:", uint256(battleNad.stats.y));	
        console.log(" i:", uint256(battleNad.stats.index));	
        console.log("========================");	
    }	

    function printBattleNadAttributes(BattleNad memory battleNad) public pure {	
        console.log("====== Attributes ======");	
        if (battleNad.stats.class == CharacterClass.Bard) {	
            console.log(" CLASS: Bard");	
        } else if (battleNad.stats.class == CharacterClass.Warrior) {	
            console.log(" CLASS: Warrior");	
        } else if (battleNad.stats.class == CharacterClass.Rogue) {	
            console.log(" CLASS: Rogue");	
        } else if (battleNad.stats.class == CharacterClass.Monk) {	
            console.log(" CLASS: Monk");	
        } else if (battleNad.stats.class == CharacterClass.Sorcerer) {	
            console.log(" CLASS: Sorcerer");	
        }	
        if (battleNad.isMonster()) {	
            console.log("-monster-");	
        } else {	
            console.log("-player-");	
        }	
        console.log(" str:", uint256(battleNad.stats.strength));	
        console.log(" vit:", uint256(battleNad.stats.vitality));	
        console.log(" dex:", uint256(battleNad.stats.dexterity));	
        console.log(" qui:", uint256(battleNad.stats.quickness));	
        console.log(" stu:", uint256(battleNad.stats.sturdiness));	
        console.log(" lck:", uint256(battleNad.stats.luck));	
        console.log("========================");	
    }	

    function printBattleNadStats(BattleNad memory battleNad) public pure {	
        console.log("======== Stats ========");	
        console.log(" wep:", uint256(battleNad.stats.weaponID));	
        console.log(" arm:", uint256(battleNad.stats.armorID));	
        console.log(" lvl:", uint256(battleNad.stats.level));	
        console.log(" exp:", uint256(battleNad.stats.experience));	
        console.log("========================");	
    }	

    function printBattleNadCombat(BattleNad memory battleNad) public pure {	
        console.log("======== Combat ========");	
        console.log(" hit points:", uint256(battleNad.stats.health));	
        console.log(" combatants:", uint256(battleNad.stats.combatants));	
        console.log(" cmbtnt lvl:", uint256(battleNad.stats.sumOfCombatantLevels));	
        console.log(" combatbmap:", uint256(battleNad.stats.combatantBitMap));	
        console.log(" nxt target:", uint256(battleNad.stats.nextTargetIndex));	
        console.log("========================");	
    }	

    function printBattleNadHandling(BattleNad memory battleNad) public pure {	
        console.log("======= Handling =======");	
        console.log(" owner:", battleNad.owner);	
        console.log(" balance:", uint256(battleNad.inventory.balance));	
        console.log(" task:", battleNad.activeTask);	
        console.log("========================");	
    }	
}	

contract BattleNadsTest is BattleNadsBaseTest {	
    
    function test_BattleNadCreation() public {
        uint256 targetBlock = block.number;
        uint256 estimatedCreationCost = battleNads.estimateBuyInAmountInMON() * 120 / 100;
        console.log("estimatedCreationCost", estimatedCreationCost);


        vm.prank(user1);	
        character1 = battleNads.createCharacter{ value: estimatedCreationCost }(	
            "Character 1", 6, 6, 5, 5, 5, 5, address(0), 0	
        );	

        _rollForward(1);	

        vm.prank(user2);	
        character2 = battleNads.createCharacter{ value: estimatedCreationCost }(	
            "Character 2", 4, 8, 4, 5, 4, 7, userSessionKey2, uint256(type(uint64).max - 1)	
        );	

        _rollForward(1);	


        vm.prank(user3);	
        character3 = battleNads.createCharacter{ value: estimatedCreationCost }(	
            "Character 3", 3, 3, 4, 4, 10, 8, userSessionKey3, uint256(type(uint64).max - 1)	
        );	

        _rollForward(1);	

        // battleNads.printBattleNad(_battleNad(1));	
        // battleNads.printBattleNad(_battleNad(2));	
        // battleNads.printBattleNad(_battleNad(3));	

        _rollForward(2);	

        uint256 i = 0;	
        while (i < 100) {	
            uint256 remainder = i % 4;	

            if (remainder == 0) {	
                vm.prank(userSessionKey3);	
                battleNads.moveNorth(character3);	
            } else if (remainder == 1) {	
                vm.prank(userSessionKey3);	
                battleNads.moveEast(character3);	
            } else if (remainder == 2) {	
                vm.prank(userSessionKey3);	
                battleNads.moveSouth(character3);	
            } else if (remainder == 3) {	
                vm.prank(userSessionKey3);	
                battleNads.moveWest(character3);	
            } 	

            if (_battleNad(3).stats.combatants != 0) {	
                break;	
            }	

            _topUpBonded(3);	

            _rollForward(1);	

            battleNads.printLogs(user3);	
            ++i;	
        }	
        require(i<100, "ERR - NO COMBAT");	

        console.log("Iterations to find combat:", i);	

        BattleNad[] memory opponents = battleNads.getCombatantBattleNads(user3);	
        require(opponents.length > 0, "ERR - OPPONENTS LENGTH 0");	

        uint256 opponentID = uint256(opponents[0].id);	
        console.logBytes32(bytes32(opponentID));	

        BattleNad memory player = _battleNad(3);	
        BattleNad memory monster = _battleNad(opponentID);	

        battleNads.printBattleNad(player);	
        battleNads.printBattleNad(monster);	

        uint256 playerHealth = uint256(player.stats.health);	
        uint256 opponentHealth = uint256(monster.stats.health);	

        console.log("playerHealth", playerHealth);	
        console.log("opponentHealth", opponentHealth);	
        i = 0;	

        vm.prank(userSessionKey3);	
        battleNads.useAbility(character3, monster.stats.index, 2);	

        while (i < 300) {	

            player = _battleNad(3);	
            monster = _battleNad(opponentID);	

            uint256 newPlayerHealth = uint256(player.stats.health);	
            uint256 newOpponentHealth = uint256(monster.stats.health);	

            if (playerHealth != newPlayerHealth || opponentHealth != newOpponentHealth) {	

                playerHealth = newPlayerHealth;	
                opponentHealth = newOpponentHealth;	
            }	

            if (playerHealth == 0) {	
                console.log(" PLAYER DIED");	
                break;	
            }	

            if (opponentHealth == 0) {	
                console.log(" MONSTER DIED");	
                break;	
            }	

            ++i;	

            _rollForward(1);	
            battleNads.printLogs(user3);	
            _topUpBonded(3);	
        }	

        console.log("");	
        console.log("Combat Over");	
        console.log("====================");	
        console.log("");	
        battleNads.printBattleNad(_battleNad(3));	
        console.log("");	
        battleNads.printBattleNad(_battleNad(opponentID));	

        // _rollForward(16);	
        // battleNads.printBattleNad(_battleNad(3));	
    }	

    function test_UpdateAndVerifySessionKey() public {	
        // 1. Define new user and session key	
        address newUser = address(4);	
        address newSessionKey = address(44);	
        vm.deal(newUser, 10 ether); // Fund the user	

        // 2. Estimate cost and create character with no initial session key	
        uint256 estimatedCreationCost = battleNads.estimateBuyInAmountInMON();	
        vm.prank(newUser);	
        battleNads.createCharacter{ value: estimatedCreationCost }(	
            "SessionTester", 5, 5, 5, 5, 5, 7, address(0), 0 // Stats: str, vit, dex, qui, stu, lck (5*5 + 7 = 32)	
        );	

        // Ensure creation task completes if necessary (optional)	
        _rollForward(1);	

        // 3. Update the session key	
        uint64 expectedExpiration = uint64(block.number + 100); // Set expiration 100 blocks in the future	

        vm.prank(newUser);	
        battleNads.updateSessionKey(newSessionKey, expectedExpiration);	

        // 4. Advance time slightly past the update transaction (RE-ADD FOR DEBUGGING)	
        _rollForward(1); // Re-adding this to force state commit before view call	

        // Call getCurrentSessionKeyData directly (view call, no prank needed)	
        SessionKeyData memory sessionKeyData_direct = battleNads.getCurrentSessionKeyData(newUser);	
        assertEq(sessionKeyData_direct.owner, newUser, "Session key data owner mismatch");	
    }
} 