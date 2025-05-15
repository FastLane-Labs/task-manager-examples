// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherit common setup and helpers
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";

// Specific imports if needed
import { Errors } from "src/battle-nads/libraries/Errors.sol";
import { Constants } from "src/battle-nads/Constants.sol";
import { BattleNad, Inventory } from "src/battle-nads/Types.sol";
import { Equipment } from "src/battle-nads/libraries/Equipment.sol";

// Tests focusing on Combat Mechanics
contract BattleNadsCombatTest is BattleNadsBaseTest, Constants {

    function setUp() public override {
        super.setUp();
        // Character 1 ("Attacker") & 2 ("Defender") created and spawned in base helper
        character1 = _createCharacterAndSpawn(1, "Attacker", 6, 6, 5, 5, 5, 5, userSessionKey1, uint64(type(uint64).max)); // Use session key for Attacker
        character2 = _createCharacterAndSpawn(2, "Defender", 5, 7, 5, 5, 5, 5, address(0), 0); // Defender has no key
        // TODO: Add logic here to force C1 and C2 into the same area if needed
        // TODO: Initiate combat between C1 and C2
    }

    function test_AllocatePoints_InCombat() public {
        // NOTE: This test uses character1 created in setUp
        bytes32 charId = character1;
        require(charId != bytes32(0), "Setup: Character 1 not created");

        // Ensure character spawned
        BattleNad memory nad_check_spawn = _battleNad(1);
        require(nad_check_spawn.stats.x != 0 || nad_check_spawn.stats.y != 0, "Setup: Character 1 did not spawn");

        // --- Cheat points onto Nad1 --- 
        uint256 slot = 3; 
        bytes32 statSlot = keccak256(abi.encode(charId, slot));
        uint256 packedData = uint256(vm.load(address(battleNads), statSlot));
        uint256 pointsOffset = 216;
        uint256 pointsMask = uint256(type(uint8).max) << pointsOffset;
        uint256 pointsToGrant = 1;
        uint256 clearedData = packedData & (~pointsMask);
        uint256 newData = clearedData | (pointsToGrant << pointsOffset);
        vm.store(address(battleNads), statSlot, bytes32(newData));
        // --- End cheat --- 

        // Initiate combat (assumes setUp places them together or aggro happens)
        BattleNad memory nad1;
        bool combatStarted = false;
        // Try attacking character 2 directly first, assuming they might spawn nearby
        BattleNad memory nad2 = _battleNad(2); // Fetch potential target
        if (nad2.id != bytes32(0) && nad2.stats.index > 0) { // Check if Nad2 exists and has a valid index
            // Check if they are in the same area (optional but good practice)
             BattleNad memory currentNad1 = _battleNad(1);
             if (currentNad1.stats.depth == nad2.stats.depth && 
                 currentNad1.stats.x == nad2.stats.x && 
                 currentNad1.stats.y == nad2.stats.y) 
             {
                 vm.prank(userSessionKey1); // Use C1's session key
                 battleNads.attack(charId, nad2.stats.index);
                 _rollForward(1);
                 nad1 = _battleNad(1); 
                 if (nad1.stats.combatants > 0) {
                     combatStarted = true;
                 }
             }
        }

        // If direct attack failed or wasn't possible, move Nad 1 until combat starts (fallback)
        if (!combatStarted) {
            for (uint i = 0; i < 50; ++i) { 
                vm.prank(userSessionKey1); // Use session key
                if (i % 4 == 0) battleNads.moveNorth(charId);
                else if (i % 4 == 1) battleNads.moveEast(charId);
                else if (i % 4 == 2) battleNads.moveSouth(charId);
                else battleNads.moveWest(charId);

                _rollForward(1);

                nad1 = _battleNad(1); 
                if (nad1.stats.combatants > 0) {
                    combatStarted = true;
                    break;
                }
            }
        }
        require(combatStarted, "Setup: Failed to initiate combat for allocate points test");

        // Attempt to allocate points while in combat
        BattleNad memory nad_before_alloc = _battleNad(1);
        vm.prank(userSessionKey1); // Use session key
        battleNads.allocatePoints(charId, 1, 0, 0, 0, 0, 0); 
        _rollForward(1);

        // Verify points were NOT allocated
        BattleNad memory nad_after_alloc = _battleNad(1);
        assertEq(nad_after_alloc.stats.strength, nad_before_alloc.stats.strength, "Strength should not change");
        assertEq(nad_after_alloc.stats.unspentAttributePoints, 1, "Unspent points should remain");
    }

    // TODO: Add tests from plan.md category 4:
    // - test_Attack_InitiateCombat
    // - test_Attack_InvalidTargetIndex
    // - test_Attack_EmptyTargetSlot
    // - test_Attack_TargetNotCombatant
    // - test_Attack_PvP_LevelCap
    // - test_CombatTurn_HitMissCrit
    // - test_CombatTurn_DamageCalculation
    // - test_CombatTurn_TargetSelection_Explicit
    // - test_CombatTurn_TargetSelection_Random
    // - test_CombatTurn_HealthRegen
    // - test_CombatTurn_Loot
    // - test_CombatTurn_Experience
    // - test_CombatEnd_Victor
    // - test_CombatEnd_MutualDeath
} 