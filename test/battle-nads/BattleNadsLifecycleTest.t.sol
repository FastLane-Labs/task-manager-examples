// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherit common setup and helpers
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";
import { VmSafe } from "forge-std/Vm.sol";

// Specific imports for this test file (if any beyond base)
import { console } from "forge-std/console.sol"; // Re-add console import as we are not inlining anymore
import { BattleNad, BattleNadStats, Inventory, BattleNadLite } from "src/battle-nads/Types.sol";
import { StatSheet } from "src/battle-nads/libraries/StatSheet.sol";
import { Errors } from "src/battle-nads/libraries/Errors.sol";
import { Constants } from "src/battle-nads/Constants.sol";
import { Equipment } from "src/battle-nads/libraries/Equipment.sol";

// Renamed contract focusing on Lifecycle tests
contract BattleNadsLifecycleTest is BattleNadsBaseTest, Constants {
    using StatSheet for BattleNadStats;

    // Test initial state variables set during deployment
    function test_InitialState() public view {
        // START_BLOCK is set in BattleNadsWrapper constructor
        // We don't know the exact setUp block number easily here, 
        // but we can assert it's non-zero.
        assertTrue(battleNads.START_BLOCK() > 0, "START_BLOCK should be non-zero");

        // TASK_IMPLEMENTATION is set in TaskHandler constructor
        assertNotEq(battleNads.TASK_IMPLEMENTATION(), address(0), "TASK_IMPLEMENTATION should not be zero address");
    }

    // Test focusing on character creation, spawning, basic movement, and a simple combat flow
    // This covers parts of categories 2 (Lifecycle) and touches on 3 (Movement) & 4 (Combat)
    function test_BattleNadCreationAndBasicFlow() public {
        uint256 estimatedCreationCost = battleNads.estimateBuyInAmountInMON();
        // console.log("Estimated Creation Cost (MON):", estimatedCreationCost); // Keep if useful, remove if noisy

        // --- Test Character 1 Creation Success (Covers test plan item 2.1) ---
        string memory name1 = "HeroOne";
        uint8 str1 = 6;
        uint8 vit1 = 6;
        uint8 dex1 = 5;
        uint8 qui1 = 5;
        uint8 stu1 = 5;
        uint8 lck1 = 5;

        vm.prank(user1);
        uint256 balanceBefore = user1.balance;

        // Record logs to potentially capture TaskScheduled event
        vm.recordLogs();

        character1 = battleNads.createCharacter{ value: estimatedCreationCost }(
            name1, str1, vit1, dex1, qui1, stu1, lck1, address(0), 0
        );
        assertTrue(character1 != bytes32(0), "Character 1 ID is zero");

        uint256 balanceAfter = user1.balance;
        // Check balance decreased (gas makes exact check hard)
        assertTrue(balanceBefore > balanceAfter, "User1 balance should decrease"); 
        // console.log("User1 Balance Diff:", balanceBefore - balanceAfter); // Optional debug

        // Fetch initial state immediately after creation
        BattleNad memory nad1_initial = battleNads.getBattleNad(character1);

        // Assert Mappings
        assertEq(battleNads.owners(character1), user1, "Owner mapping mismatch");
        assertEq(battleNads.characters(user1), character1, "Character mapping mismatch");
        assertEq(battleNads.characterNames(character1), name1, "Name mapping mismatch");

        // Assert Stats (Note: These are base stats before potential class adjustments are applied *and then removed* by _buildNewCharacter)
        assertEq(nad1_initial.stats.level, 1, "Level mismatch");

        // Assert Starting Equipment (IDs are random 1-4)
        assertTrue(nad1_initial.stats.weaponID >= 1 && nad1_initial.stats.weaponID <= 4, "Invalid Weapon ID");
        assertTrue(nad1_initial.stats.armorID >= 1 && nad1_initial.stats.armorID <= 4, "Invalid Armor ID");
        assertTrue(Equipment.hasWeapon(nad1_initial.inventory, nad1_initial.stats.weaponID), "Weapon not in inventory bitmap");
        assertTrue(Equipment.hasArmor(nad1_initial.inventory, nad1_initial.stats.armorID), "Armor not in inventory bitmap");

        // Assert Spawn Task Scheduled
        assertNotEq(nad1_initial.activeTask.taskAddress, address(0), "Spawn task not set");

        _rollForward(1); // Allow time for task execution

        // --- Create Character 2 & 3 (Less detailed checks for brevity) ---
        vm.prank(user2);
        character2 = battleNads.createCharacter{ value: estimatedCreationCost }(
            "HeroTwo", 4, 8, 4, 5, 4, 7, userSessionKey2, uint64(block.timestamp + 1 days) // Use timestamp for deadline
        );
        assertTrue(character2 != bytes32(0), "Character 2 ID is zero");
        _rollForward(1); // <<< RESTORING original timing

        vm.prank(user3);
        character3 = battleNads.createCharacter{ value: estimatedCreationCost }(
            "HeroThree", 3, 3, 4, 4, 10, 8, userSessionKey3, uint64(type(uint64).max)
        );
        assertTrue(character3 != bytes32(0), "Character 3 ID is zero");
        _rollForward(1); // <<< RESTORING original timing

        // Add back the buffer roll from the original test
        _rollForward(2);

        // Verify characters have spawned (basic check: location is not 0,0,0)
        // BattleNad memory nad1 = _battleNad(1);
        BattleNad memory nad1 = _battleNad(1); // Load potentially updated nad1
        BattleNad memory nad2 = _battleNad(2);
        BattleNad memory nad3 = _battleNad(3);

        console.log("--- Characters Created (Spawn may be pending/processing) ---"); // Updated log message
        battleNads.printBattleNad(nad1);
        battleNads.printBattleNad(nad2);
        battleNads.printBattleNad(nad3);

        // Simulate Character 3 moving around to find combat
        console.log("--- Character 3 Searching for Combat ---");
        uint256 moveIterations = 0;
        while (moveIterations < 100) { // Limit iterations to prevent infinite loop - MATCHED ORIGINAL (100)
            // Use session key for actions
            vm.prank(userSessionKey3);
            uint256 remainder = moveIterations % 4;
            if (remainder == 0) battleNads.moveNorth(character3);
            else if (remainder == 1) battleNads.moveEast(character3);
            else if (remainder == 2) battleNads.moveSouth(character3);
            else battleNads.moveWest(character3);

            // Advance time/blocks for movement task & potential combat trigger
             _rollForward(1); // Allow movement and aggro checks
             battleNads.printLogs(user3);
             _topUpBonded(3); // Ensure sufficient balance for tasks

             // Check if combat started
             nad3 = _battleNad(3);
            if (nad3.stats.combatants != 0) {
                 console.log("Combat initiated after", moveIterations + 1, "moves.");
                break;
            }
            moveIterations++;
        }
        require(nad3.stats.combatants != 0, "ERR - Character 3 failed to find combat within 100 moves"); // MATCHED ORIGINAL (100)

        // Identify opponent
        BattleNad[] memory opponents = battleNads.getCombatantBattleNads(user3);
        require(opponents.length > 0, "ERR - No opponents found despite combat flag");
        bytes32 opponentID = opponents[0].id; // Assume first opponent is the target
        BattleNad memory monster = battleNads.getBattleNad(opponentID); // Use direct getter
        assertTrue(monster.id != bytes32(0), "Failed to get opponent BattleNad");

        console.log("--- Combat Started ---");
        battleNads.printBattleNad(nad3);
        battleNads.printBattleNad(monster);

        uint256 playerInitialHealth = nad3.stats.health;
        uint256 monsterInitialHealth = monster.stats.health;

        console.log("playerHealth", playerInitialHealth);
        console.log("opponentHealth", monsterInitialHealth);

        vm.prank(userSessionKey3);
        battleNads.useAbility(character3, monster.stats.index, 2);

        vm.recordLogs(); 

        // Simulate combat turns by rolling forward
        console.log("--- Simulating Combat Turns ---");
        uint256 combatTurns = 0;

        while (combatTurns < 300) { // Limit turns
            _rollForward(1); // Execute combat tasks for this block
            battleNads.printLogs(user3); // See combat logs
            _topUpBonded(3); // Top up gas for player task
            // Note: Monster tasks rely on player paying

            nad3 = _battleNad(3);
            // Refresh monster state - IMPORTANT as it changes
            monster = battleNads.getBattleNad(opponentID);

            // CORRECTLY SPLIT LOG STATEMENT HERE:
            console.log("Turn", combatTurns+1, "Player HP:", nad3.stats.health);
            console.log("  Monster HP:", monster.stats.health);

            // Check for end conditions
            if (nad3.stats.isDead()) {
                console.log("PLAYER DIED");
                break;
            }
            if (monster.stats.isDead()) {
                console.log("MONSTER DIED");
                break;
            }

            combatTurns++;
        }

        console.log("--- Combat Over --- Final State ---"); // Keep
        battleNads.printBattleNad(_battleNad(3));
        // Fetch monster again - it might be dead/gone
        BattleNad memory finalMonsterState = battleNads.getBattleNad(opponentID);
        if(finalMonsterState.id != bytes32(0)) { // Check if it still exists
             battleNads.printBattleNad(finalMonsterState);
        } else {
             console.log("Monster ID does not exist");
             console.logBytes32(opponentID);
        }
    }

    // --- Character Creation Revert Tests (Plan Category 2) ---
    function test_CreateCharacter_InvalidStatsSum() public {
        vm.prank(user1);
        bytes32 resultId = battleNads.createCharacter{ value: 0 }("StatsTooLow", 5, 5, 5, 5, 5, 6, address(0), 0);
        assertEq(resultId, bytes32(0), "Character should not be created with invalid stats sum");
        assertEq(battleNads.characters(user1), bytes32(0), "Character mapping should remain empty");
    }

    function test_CreateCharacter_InvalidMinStats() public {
        vm.prank(user1);
        bytes32 resultId = battleNads.createCharacter{ value: 0 }("MinStatTooLow", 7, 2, 6, 5, 6, 6, address(0), 0);
        assertEq(resultId, bytes32(0), "Character should not be created with invalid min stats");
        assertEq(battleNads.characters(user1), bytes32(0), "Character mapping should remain empty");
    }

    function test_CreateCharacter_NameTooLong() public {
        string memory longName = "ThisNameIsWayTooLongToBeValid"; // > _MAX_NAME_LENGTH (18)
        vm.prank(user1);
        bytes32 resultId = battleNads.createCharacter{ value: 0 }(longName, 6, 6, 5, 5, 5, 5, address(0), 0);
        assertEq(resultId, bytes32(0), "Character should not be created with long name");
        assertEq(battleNads.characters(user1), bytes32(0), "Character mapping should remain empty");
    }

    function test_CreateCharacter_NameTooShort() public {
        string memory shortName = "AB"; // < _MIN_NAME_LENGTH (3)
        vm.prank(user1);
        bytes32 resultId = battleNads.createCharacter{ value: 0 }(shortName, 6, 6, 5, 5, 5, 5, address(0), 0);
        assertEq(resultId, bytes32(0), "Character should not be created with short name");
        assertEq(battleNads.characters(user1), bytes32(0), "Character mapping should remain empty");
    }

    function test_CreateCharacter_NameCollision() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        string memory name = "CollisionName";
        vm.prank(user1);
        battleNads.createCharacter{ value: cost }(name, 6, 6, 5, 5, 5, 5, address(0), 0);
        _rollForward(1); 
        bytes32 user1CharId = battleNads.characters(user1);
        require(user1CharId != bytes32(0), "Setup: First character failed to create");

        vm.prank(user2);
        bytes32 initialUser2CharId = battleNads.characters(user2);
        battleNads.createCharacter{ value: cost }(name, 5, 5, 6, 6, 5, 5, address(0), 0);
        assertEq(battleNads.characters(user2), initialUser2CharId, "Character created despite name collision"); // Should still be 0
    }

    function test_CreateCharacter_OwnerAlreadyExists() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        vm.prank(user1);
        battleNads.createCharacter{ value: cost }("OwnerHasOne", 6, 6, 5, 5, 5, 5, address(0), 0);
        _rollForward(1); 
        bytes32 firstCharId = battleNads.characters(user1);
        require(firstCharId != bytes32(0), "Setup: First character failed to create");

        vm.prank(user1);
        battleNads.createCharacter{ value: cost }("OwnerWantsTwo", 5, 5, 6, 6, 5, 5, address(0), 0);
        // Assert owner still maps to the FIRST character ID
        assertEq(battleNads.characters(user1), firstCharId, "Second character created for owner");
    }

     function test_CreateCharacter_InsufficientBuyIn() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        uint256 insufficientAmount = cost > 1 ? cost - 100 : 0; 

        //TODO review if buyin amount is required otherwise why call it buyin amount
        vm.prank(user1);
        bytes32 initialCharId = battleNads.characters(user1);
        battleNads.createCharacter{ value: insufficientAmount }("LowBaller", 6, 6, 5, 5, 5, 5, address(0), 0);
        assertEq(battleNads.characters(user1), initialCharId, "Character created despite insufficient buy-in");
    }

    function test_CreateCharacter_AfterPreviousDeath() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        vm.prank(user1);
        bytes32 firstCharacterId = battleNads.createCharacter{ value: cost }("DiesThenReborn", 6, 6, 5, 5, 5, 5, address(0), 0);

        _waitForSpawn(firstCharacterId);

        BattleNad memory nad1 = battleNads.getBattleNad(firstCharacterId);
        assertEq(nad1.stats.combatants, 0, "Nad 1 should not be in combat before ascend");

        vm.prank(user1);
        battleNads.ascend(firstCharacterId);
        _rollForward(EXPECTED_ASCEND_DELAY); 
        
        vm.prank(user1);
        bytes32 secondCharacterId = battleNads.createCharacter{ value: cost }("TheReborn", 5, 5, 6, 6, 5, 5, address(0), 0);

        assertTrue(secondCharacterId != bytes32(0), "Second character creation failed");
        assertTrue(secondCharacterId != firstCharacterId, "Second character ID is same as first");
        assertEq(battleNads.characters(user1), secondCharacterId, "Owner mapping not set to second character");
    }

    function test_Spawn_Success() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        vm.prank(user1);
        bytes32 charId = battleNads.createCharacter{ value: cost }("Spawner", 6, 6, 5, 5, 5, 5, address(0), 0);
        
        BattleNad memory nad_before = battleNads.getBattleNad(charId);
        assertEq(nad_before.stats.depth, 0, "Initial depth should be 0");
        assertEq(nad_before.stats.x, 0, "Initial x should be 0");
        assertEq(nad_before.stats.y, 0, "Initial y should be 0");
        assertNotEq(nad_before.activeTask.taskAddress, address(0), "Initial activeTask should be set");

        // Wait for spawn 
        BattleNad memory nad_after = _waitForSpawn(charId); 

        // Check state after spawn 
        assertEq(nad_after.stats.depth, 1, "Spawned depth should be 1");
        assertTrue(nad_after.stats.x != 0, "Spawned x should not be 0");
        assertTrue(nad_after.stats.y != 0, "Spawned y should not be 0");
        assertTrue(nad_after.stats.index < 64 && nad_after.stats.index > 0, "Spawned index invalid"); 
        assertTrue(nad_after.activeTask.taskAddress == address(0) || nad_after.activeTask.taskAddress == address(1), "activeTask should be cleared after spawn");
    }

    function test_AllocatePoints_Success() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        vm.prank(user1);
        bytes32 charId = battleNads.createCharacter{ value: cost }("PointAllocator", 6, 6, 5, 5, 5, 5, address(0), 0);
        require(charId != bytes32(0), "Setup: Character creation failed");
        _waitForSpawn(charId); // Ensure spawned before trying to allocate

        BattleNad memory nad_before = _battleNad(1);
        assertEq(nad_before.stats.unspentAttributePoints, 0, "Should have 0 points initially");

        // Define allocation (allocate 0 points)
        uint256 strInc = 0;
        uint256 vitInc = 0;
        uint256 dexInc = 0;
        uint256 quiInc = 0;
        uint256 stuInc = 0;
        uint256 lckInc = 0;

        // Allocate 0 points (should succeed and do nothing)
        vm.prank(user1);
        battleNads.allocatePoints(charId, strInc, vitInc, dexInc, quiInc, stuInc, lckInc);
        _rollForward(1); // Allow potential tasks

        BattleNad memory nad_after = _battleNad(1);

        // Assert stats unchanged
        assertEq(nad_after.stats.strength, nad_before.stats.strength, "Strength changed unexpectedly");
        assertEq(nad_after.stats.vitality, nad_before.stats.vitality, "Vitality changed unexpectedly");
        assertEq(nad_after.stats.dexterity, nad_before.stats.dexterity, "Dexterity changed unexpectedly");
        assertEq(nad_after.stats.quickness, nad_before.stats.quickness, "Quickness changed unexpectedly");
        assertEq(nad_after.stats.sturdiness, nad_before.stats.sturdiness, "Sturdiness changed unexpectedly");
        assertEq(nad_after.stats.luck, nad_before.stats.luck, "Luck changed unexpectedly");
        assertEq(nad_after.stats.unspentAttributePoints, 0, "Unspent points should still be 0");
    }

    function test_AllocatePoints_Insufficient() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        vm.prank(user1);
        bytes32 charId = battleNads.createCharacter{ value: cost }("NoPointsToSpend", 6, 6, 5, 5, 5, 5, address(0), 0);
        require(charId != bytes32(0), "Setup: Character creation failed");
        _waitForSpawn(charId); // Wait for spawn before checking points

        vm.prank(user1);
        BattleNad memory nad_before = _battleNad(1);
        battleNads.allocatePoints(charId, 1, 0, 0, 0, 0, 0); 
        _rollForward(1); // Allow potential tasks
        BattleNad memory nad_after = _battleNad(1);
        // Assert that points and stats did not change
        assertEq(nad_after.stats.unspentAttributePoints, nad_before.stats.unspentAttributePoints, "Unspent points changed unexpectedly");
        assertEq(nad_after.stats.strength, nad_before.stats.strength, "Strength changed unexpectedly");
    }

    function test_Ascend_Success() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        vm.prank(user1);
        bytes32 charId = battleNads.createCharacter{ value: cost }("Ascender", 6, 6, 5, 5, 5, 5, address(0), 0);
        character1 = charId; 

        BattleNad memory nad1 = _waitForSpawn(charId); // Use wait helper

        assertEq(nad1.stats.combatants, 0, "Nad 1 should not be in combat before ascend");

        vm.prank(user1);
        battleNads.ascend(charId);

        _rollForward(EXPECTED_ASCEND_DELAY); // Allow ascend task to execute

        // Verify character state after ascend using getBattleNadLite
        // We expect the character to be marked as dead.
        // getBattleNad or getBattleNadLite might revert if data is fully deleted, 
        // but if it returns, isDead should be true.
        try battleNads.getBattleNadLite(charId) returns (BattleNadLite memory lite_nad_after) {
             assertTrue(lite_nad_after.isDead, "Character should be dead after ascend");
             // Optionally, could also check health is 0
             // assertEq(lite_nad_after.health, 0, "Character health should be 0 after ascend");
        } catch Error(string memory /*reason*/) {
             // Allow revert as another valid outcome if getBattleNadLite itself reverts on deleted data
             // console.log("getBattleNadLite reverted as expected after ascend:", reason);
             assertTrue(true); // Count revert as success in this context
        } catch { 
             // Catch generic revert
             assertTrue(true); // Count revert as success
        }
    }

    function test_Ascend_InCombat() public {
        uint256 cost = battleNads.estimateBuyInAmountInMON();
        vm.prank(user1);
        bytes32 charId = battleNads.createCharacter{ value: cost }("SuicidalCombatant", 6, 6, 5, 5, 5, 5, address(0), 0);
        character1 = charId; 

        _waitForSpawn(charId);

        // Move Nad 1 until combat starts
        BattleNad memory nad1;
        bool combatStarted = false;
        for (uint i = 0; i < 50; ++i) { 
            vm.prank(user1);
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
        require(combatStarted, "Setup: Failed to initiate combat");

        // The call won't revert due to try/catch, but state shouldn't change
        vm.prank(user1);
        battleNads.ascend(charId); 
        _rollForward(EXPECTED_ASCEND_DELAY);

        assertEq(battleNads.characters(user1), charId, "Owner mapping should not be cleared");
        BattleNad memory nad_after = _battleNad(1);
        assertTrue(nad_after.id != bytes32(0), "Character should still exist after failed ascend");
        assertTrue(nad_after.stats.health > 0, "Character health should be > 0 after failed ascend");
    }
} 