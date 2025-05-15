// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherit common setup and helpers
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";

// Specific imports if needed
import { CharacterClass, Ability } from "src/battle-nads/Types.sol";

// Tests focusing on Class Abilities
contract BattleNadsAbilityTest is BattleNadsBaseTest {

     function setUp() public override {
        super.setUp();
        // Additional setup specific to ability tests, e.g., create characters of specific classes.
        // Might need helper to force class or create many characters until desired class is found.
        character1 = _createCharacterAndSpawn(1, "AbilityUser", 6, 6, 5, 5, 5, 5, address(0), 0);
        character2 = _createCharacterAndSpawn(2, "AbilityTarget", 5, 7, 5, 5, 5, 5, address(0), 0);
         // TODO: Ensure users are in the same area for targeted abilities
    }

    // TODO: Add tests from plan.md category 5:
    // Create tests for each ability for each class:
    // e.g., test_Ability_Warrior_ShieldBash_Success
    // e.g., test_Ability_Rogue_ApplyPoison_MultiStage
    // etc.
    // Cover success, cooldown, invalid target, status effects, multi-stage logic, interruption.
} 