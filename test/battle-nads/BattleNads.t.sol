// SPDX-License-Identifier: MIT	
pragma solidity ^0.8.19;	
	
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";
import { VmSafe } from "forge-std/Vm.sol";

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

import { SessionKey, SessionKeyData, GasAbstractionTracker  } from "lib/fastlane-contracts/src/common/relay/types/GasRelayTypes.sol";

import { BattleNadsEntrypoint } from "src/battle-nads/Entrypoint.sol";	
import { BattleNadsImplementation } from "src/battle-nads/tasks/BattleNadsImplementation.sol";	

import { StatSheet } from "../../src/battle-nads/libraries/StatSheet.sol";	

import {console} from "forge-std/console.sol";	


contract BattleNadsTest is BattleNadsBaseTest {	
    
    function test_BattleNadCreation2() public {
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
        // battleNads.useAbility(character3, monster.stats.index, 2);	

        while (i < 100) {	

            player = _battleNad(3);	
            monster = _battleNad(opponentID);	

            uint256 newPlayerHealth = uint256(player.stats.health);	
            uint256 newOpponentHealth = uint256(monster.stats.health);
            /*
            console.log("");	
            console.log("block number", block.number);
            console.log("newPlayerHealth", newPlayerHealth);
            console.log("newOpponentHealth", newOpponentHealth);
            */

            if (playerHealth != newPlayerHealth || opponentHealth != newOpponentHealth) {	
                
                /*
                if (playerHealth > newPlayerHealth) {
                    console.log("damage to player", playerHealth - newPlayerHealth);
                }
                if (opponentHealth > newOpponentHealth) {
                    console.log("damage to monster", opponentHealth - newOpponentHealth);
                }
                */

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

            // console.log("===");

            _rollForward(2);	
            // battleNads.printLogs(user3);	
            _topUpBonded(3);		
        }	

        monster = _battleNad(opponentID);
        assertEq(monster.stats.health, uint16(0), "Monster not dead");

        console.log("");	
        console.log("Combat Over");	
        console.log("====================");	
        console.log("");	
        /*
        battleNads.printBattleNad(_battleNad(3));	
        console.log("");	
        battleNads.printBattleNad(_battleNad(opponentID));	

        console.log("=FINAL=");
        */
        _rollForward(2);		
        /*
        console.log("");	
        battleNads.printBattleNad(_battleNad(3));	
        console.log("");	
        battleNads.printBattleNad(_battleNad(opponentID));	

        _rollForward(2); console.log("");	
        battleNads.printBattleNad(_battleNad(3));	
        console.log("");	
        battleNads.printBattleNad(_battleNad(opponentID));	
        */

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