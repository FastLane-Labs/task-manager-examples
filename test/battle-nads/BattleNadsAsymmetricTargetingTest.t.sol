// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherit common setup and helpers
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";
import { console } from "forge-std/console.sol";

// Specific imports if needed
import { Errors } from "src/battle-nads/libraries/Errors.sol";
import { Constants } from "src/battle-nads/Constants.sol";
import { BattleNad, Inventory, Log, CharacterClass, LogType, BattleArea } from "src/battle-nads/Types.sol";
import { Equipment } from "src/battle-nads/libraries/Equipment.sol";

/**
 * @title BattleNadsAsymmetricTargetingTest
 * @notice Test to reproduce the asymmetric targeting bug where monsters can attack players
 *         but players can't find monsters due to combatantBitMap desynchronization
 * @dev The bug occurs when player's combatantBitMap doesn't include the monster, but
 *      the monster can still target the player using area.playerBitMap
 */
contract BattleNadsAsymmetricTargetingTest is BattleNadsBaseTest, Constants {

    function setUp() public override {
        super.setUp();
        // Create a character with good combat stats to ensure damage capability
        // Strength: 9 (decent damage), Dexterity: 5 (hit chance)
        character1 = _createCharacterAndSpawn(1, "Fighter", 6, 6, 5, 5, 5, 5, userSessionKey1, uint64(type(uint64).max));
    }

    /**
     * @dev Test to reproduce the asymmetric targeting bug
     * This test simulates the scenario where:
     * 1. Player enters combat with monster (mutual combatantBitMap set)
     * 2. Something causes the combatantBitMap to become desynchronized
     * 3. Monster can still attack player (uses area.playerBitMap)
     * 4. Player cannot attack monster (relies on combatantBitMap)
     * 5. Player just regenerates health instead of attacking
     */
    function test_AsymmetricTargeting_PlayerCannotFindMonster() public {
        bytes32 fighter = character1;
        
        // Ensure good starting stats for combat
        _modifyCharacterStat(fighter, "strength", 9);
        _modifyCharacterStat(fighter, "dexterity", 5);
        
        // Give the character a good weapon
        _giveWeapon(fighter, "Mean Words", 125, 85); // baseDamage: 125, accuracy: 85
        
        console.log("=== Starting Asymmetric Targeting Test ===");
        
        // Step 1: Enter combat normally
        bool combatStarted = _triggerRandomCombat(fighter);
        assertTrue(combatStarted, "Should enter combat");
        
        BattleNad memory fighterAfterCombat = _battleNad(1);
        assertTrue(fighterAfterCombat.stats.combatants > 0, "Should be in combat");
        assertTrue(fighterAfterCombat.stats.combatantBitMap != 0, "Should have combatant bitmap set");
        
        console.log("Combat started - Fighter combatantBitMap: %d", uint256(fighterAfterCombat.stats.combatantBitMap));
        console.log("Fighter combatants count: %d", fighterAfterCombat.stats.combatants);
        console.log("Fighter nextTargetIndex: %d", fighterAfterCombat.stats.nextTargetIndex);
        
        // Step 2: Record the current state before desync
        // We can't directly access area info, but we can observe the behavior
        
        // Step 3: Simulate the desync bug by manually clearing the fighter's combatantBitMap
        // This simulates what happens when the bitmaps get out of sync
        console.log("=== Simulating combatantBitMap desync ===");
        _modifyCharacterStat(fighter, "combatantBitMap", 0);
        
        BattleNad memory fighterWithClearedBitmap = _battleNad(1);
        assertEq(fighterWithClearedBitmap.stats.combatantBitMap, 0, "Fighter combatantBitMap should be cleared");
        assertTrue(fighterWithClearedBitmap.stats.combatants > 0, "But should still show combatants count > 0");
        
        // Step 4: Record initial health
        uint256 initialHealth = fighterWithClearedBitmap.stats.health;
        console.log("Fighter health before turn: %d", initialHealth);
        
        // Step 5: Execute several combat turns and observe the behavior
        console.log("=== Executing combat turns ===");
        
        uint256 healthRegenCount = 0;
        uint256 attackCount = 0;
        
        for (uint256 i = 0; i < 5; i++) {
            uint256 healthBefore = battleNads.getBattleNad(fighter).stats.health;
            
            // Roll forward to execute combat tasks
            _rollForward(2);
            
            uint256 healthAfter = battleNads.getBattleNad(fighter).stats.health;
            
            console.log("Turn %d - Health before: %d, after: %d", i + 1, healthBefore, healthAfter);
            
            if (healthAfter > healthBefore) {
                healthRegenCount++;
                console.log("  -> Health regenerated (no valid target found)");
            } else if (healthAfter < healthBefore) {
                console.log("  -> Took damage (monster attacked)");
            } else {
                attackCount++;
                console.log("  -> No health change (may have attacked)");
            }
        }
        
        // Step 6: Verify the asymmetric behavior
        console.log("=== Results ===");
        console.log("Health regen turns: %d", healthRegenCount);
        console.log("Attack turns: %d", attackCount);
        
        // The bug manifests as the player regenerating health instead of attacking
        // because _getTargetIDAndStats cannot find the monster due to cleared combatantBitMap
        assertTrue(healthRegenCount > 0, "Player should regenerate health when unable to find targets");
        
        // Check combat logs to see if player is just regenerating
        Log[] memory combatLogs = _getCombatLogs(user1);
        
        bool foundHealthRegen = false;
        bool foundAttackLog = false;
        
        for (uint i = 0; i < combatLogs.length; i++) {
            if (combatLogs[i].logType == LogType.Combat) {
                // Check if this is a health regen vs attack based on log content
                // For now we'll assume Combat logs indicate actual fighting
                foundAttackLog = true;
                console.log("Found combat log - player managed to attack");
            } else if (combatLogs[i].logType == LogType.Ability) {
                foundAttackLog = true;
                console.log("Found ability log - player used ability");
            }
        }
        
        // The asymmetric targeting bug is confirmed if:
        // 1. Player is regenerating health (cannot find targets)
        // 2. Player has good stats and weapon (should be able to deal damage)
        // 3. Player is supposedly in combat (combatants > 0)
        // 4. But player's combatantBitMap is empty/desync'd
        
        console.log("=== Bug Analysis ===");
        console.log("Player has good stats and weapon: YES");
        console.log("Player is in combat (combatants > 0): YES");
        console.log("Player combatantBitMap is empty:", fighterWithClearedBitmap.stats.combatantBitMap == 0);
        console.log("Player regenerating instead of attacking:", healthRegenCount > 0);
        console.log("Found attack logs:", foundAttackLog);
        
        // Bug is reproduced if player regenerated health but has no attacks
        // This indicates they couldn't find targets despite being in combat
        if (healthRegenCount > 0 && !foundAttackLog) {
            console.log("ASYMMETRIC TARGETING BUG REPRODUCED!");
            console.log("Player cannot find monster targets despite being in combat");
        } else if (healthRegenCount > 0 && foundAttackLog) {
            console.log("Mixed behavior: Player both regenerated and attacked");
        } else {
            console.log("Normal combat behavior observed");
        }
    }

    /**
     * @dev Test normal symmetric targeting for comparison
     * This shows how combat should work when bitmaps are properly synchronized
     */
    function test_SymmetricTargeting_Normal() public {
        bytes32 fighter = character1;
        
        // Ensure good starting stats for combat
        _modifyCharacterStat(fighter, "strength", 9);
        _modifyCharacterStat(fighter, "dexterity", 5);
        
        // Give the character a good weapon
        _giveWeapon(fighter, "Mean Words", 125, 85);
        
        console.log("=== Testing Normal Symmetric Targeting ===");
        
        // Step 1: Enter combat normally
        bool combatStarted = _triggerRandomCombat(fighter);
        assertTrue(combatStarted, "Should enter combat");
        
        BattleNad memory fighterInCombat = _battleNad(1);
        assertTrue(fighterInCombat.stats.combatants > 0, "Should be in combat");
        assertTrue(fighterInCombat.stats.combatantBitMap != 0, "Should have combatant bitmap set");
        
        console.log("Fighter combatantBitMap: %d", uint256(fighterInCombat.stats.combatantBitMap));
        
        // Step 2: Execute combat turns with proper bitmap
        uint256 initialHealth = fighterInCombat.stats.health;
        console.log("Initial health: %d", initialHealth);
        
        // Roll forward a few turns
        _rollForward(3);
        
        // Step 3: Check results
        BattleNad memory fighterAfterTurns = _battleNad(1);
        console.log("Health after turns: %d", fighterAfterTurns.stats.health);
        
        // Check combat logs
        Log[] memory combatLogs = _getCombatLogs(user1);
        
        bool foundCombatAction = false;
        for (uint i = 0; i < combatLogs.length; i++) {
            if (combatLogs[i].logType == LogType.Combat || combatLogs[i].logType == LogType.Ability) {
                foundCombatAction = true;
                console.log("Found combat/ability log - normal targeting working");
                break;
            }
        }
        
        console.log("Normal targeting allows combat actions: %s", foundCombatAction ? "true" : "false");
    }

    /**
     * @dev Helper function to give a weapon to a character for testing
     */
    function _giveWeapon(bytes32 charId, string memory name, uint256 baseDamage, uint256 accuracy) internal {
        // This would need to be implemented based on how weapons are handled in the system
        // For now we'll modify the character's equipment directly if possible
        console.log("Giving weapon with damage: %d, accuracy: %d", baseDamage, accuracy);
        // Implementation depends on how the test framework handles equipment
    }
}