// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherit common setup and helpers

import { VmSafe } from "forge-std/Vm.sol";
import { console } from "forge-std/console.sol";

import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";
import { Errors } from  "src/battle-nads/libraries/Errors.sol";
import { Events } from "src/battle-nads/libraries/Events.sol";
import { BattleNad } from "src/battle-nads/Types.sol";
import { Constants } from "src/battle-nads/Constants.sol";

// Specific imports if needed

// Tests focusing on Movement and Location Logic
contract BattleNadsMovementTest is BattleNadsBaseTest, Constants {

    function setUp() public override {
        super.setUp();
        // Character 1 ("Mover") created and spawned with userSessionKey1
        character1 = _createCharacterAndSpawn(1, "Mover", 6, 6, 5, 5, 5, 5, userSessionKey1, uint64(type(uint64).max));
    }

    function test_Move_Valid_North() public {
        require(character1 != bytes32(0), "Setup: Character 1 not created");
        
        // Wait for character to spawn (up to a timeout)
        BattleNad memory nad_before;
        bool spawned = false;
        for (uint i = 0; i < 20; ++i) { // Timeout after ~20 blocks post initial spawn delay
            nad_before = _battleNad(1);
            if (nad_before.stats.x != 0 || nad_before.stats.y != 0) {
                spawned = true;
                break;
            }
            _rollForward(1); // Roll 1 block and retry
        }
        require(spawned, "Setup: Character 1 did not spawn within timeout");

        uint8 initialX = nad_before.stats.x;
        uint8 initialY = nad_before.stats.y;

        vm.recordLogs();

        // Move North using Session Key
        vm.prank(userSessionKey1);
        battleNads.moveNorth(character1);

        _rollForward(1); 

        BattleNad memory nad_after = _battleNad(1);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        assertEq(nad_after.stats.x, initialX, "X coordinate should not change");
        assertEq(nad_after.stats.y, initialY + 1, "Y coordinate did not increment correctly");

        // Assert correct events were emitted (basic check for now)
        // TODO: Refine event assertion to check topics/data more precisely
        assertTrue(_findLog(logs, Events.CharacterLeftArea.selector), "CharacterLeftArea event not found");
        assertTrue(_findLog(logs, Events.CharacterEnteredArea.selector), "CharacterEnteredArea event not found");
    }

    function test_Move_Valid_South() public {
        require(character1 != bytes32(0), "Setup: Character 1 not created");
        BattleNad memory nad_spawned = _waitForSpawn(character1);
        uint8 initialX = nad_spawned.stats.x;
        uint8 initialY = nad_spawned.stats.y;

        vm.recordLogs();
        vm.prank(userSessionKey1);
        battleNads.moveSouth(character1);
        _rollForward(1); 
        BattleNad memory nad_after = _battleNad(1);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        assertEq(nad_after.stats.x, initialX, "X coordinate should not change");
        assertEq(nad_after.stats.y, initialY - 1, "Y coordinate did not decrement correctly");
        assertTrue(_findLog(logs, Events.CharacterLeftArea.selector), "CharacterLeftArea event not found");
        assertTrue(_findLog(logs, Events.CharacterEnteredArea.selector), "CharacterEnteredArea event not found");
    }

    function test_Move_Valid_East() public {
        require(character1 != bytes32(0), "Setup: Character 1 not created");
        BattleNad memory nad_spawned = _waitForSpawn(character1);
        uint8 initialX = nad_spawned.stats.x;
        uint8 initialY = nad_spawned.stats.y;

        vm.recordLogs();
        vm.prank(userSessionKey1);
        battleNads.moveEast(character1);
        _rollForward(1);
        BattleNad memory nad_after = _battleNad(1);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        assertEq(nad_after.stats.x, initialX + 1, "X coordinate did not increment correctly");
        assertEq(nad_after.stats.y, initialY, "Y coordinate should not change");
        assertTrue(_findLog(logs, Events.CharacterLeftArea.selector), "CharacterLeftArea event not found");
        assertTrue(_findLog(logs, Events.CharacterEnteredArea.selector), "CharacterEnteredArea event not found");
    }

    function test_Move_Valid_West() public {
        require(character1 != bytes32(0), "Setup: Character 1 not created");
        BattleNad memory nad_spawned = _waitForSpawn(character1);
        uint8 initialX = nad_spawned.stats.x;
        uint8 initialY = nad_spawned.stats.y;

        vm.recordLogs();
        vm.prank(userSessionKey1);
        battleNads.moveWest(character1);
        _rollForward(1);
        BattleNad memory nad_after = _battleNad(1);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        assertEq(nad_after.stats.x, initialX - 1, "X coordinate did not decrement correctly");
        assertEq(nad_after.stats.y, initialY, "Y coordinate should not change");
        assertTrue(_findLog(logs, Events.CharacterLeftArea.selector), "CharacterLeftArea event not found");
        assertTrue(_findLog(logs, Events.CharacterEnteredArea.selector), "CharacterEnteredArea event not found");
    }

    function test_Move_Boundaries() public {
        require(character1 != bytes32(0), "Setup: Character 1 not created");
        BattleNad memory nad_spawned = _waitForSpawn(character1);
        bytes32 charId = character1;
        address key = userSessionKey1;
        uint8 currentY = nad_spawned.stats.y; 
        uint8 currentX = nad_spawned.stats.x;

        // --- Test Left Boundary (x=1) ---
        _teleportCharacter(charId, 1, currentY); 
        BattleNad memory nad_beforeWest = _battleNad(1); 
        // Add check here to ensure teleport worked if needed, though subsequent checks imply it
        assertEq(nad_beforeWest.stats.x, 1, "Teleport West failed"); 

        vm.prank(key);
        battleNads.moveWest(charId); 
        _rollForward(1); // Allow task processing 
        BattleNad memory nad_afterWest = _battleNad(1);
        assertEq(nad_afterWest.stats.x, nad_beforeWest.stats.x, "West Boundary: X should not change");
        assertEq(nad_afterWest.stats.y, nad_beforeWest.stats.y, "West Boundary: Y should not change");
        
        // --- Test Bottom Boundary (y=1) ---
        currentX = nad_afterWest.stats.x; // Use potentially updated X (should still be 1)
        _teleportCharacter(charId, currentX, 1);
        BattleNad memory nad_beforeSouth = _battleNad(1);
        assertEq(nad_beforeSouth.stats.y, 1, "Teleport South failed");

        vm.prank(key);
        battleNads.moveSouth(charId);
        _rollForward(1);
        BattleNad memory nad_afterSouth = _battleNad(1);
        assertEq(nad_afterSouth.stats.x, nad_beforeSouth.stats.x, "South Boundary: X should not change");
        assertEq(nad_afterSouth.stats.y, nad_beforeSouth.stats.y, "South Boundary: Y should not change");

        // --- Test Right Boundary (x=MAX_DUNGEON_X) ---
        currentY = nad_afterSouth.stats.y; // Use potentially updated Y (should still be 1)
        _teleportCharacter(charId, MAX_DUNGEON_X, currentY);
        BattleNad memory nad_beforeEast = _battleNad(1);
        assertEq(nad_beforeEast.stats.x, MAX_DUNGEON_X, "Teleport East failed");

        vm.prank(key);
        battleNads.moveEast(charId);
        _rollForward(1);
        BattleNad memory nad_afterEast = _battleNad(1);
        assertEq(nad_afterEast.stats.x, nad_beforeEast.stats.x, "East Boundary: X should not change");
        assertEq(nad_afterEast.stats.y, nad_beforeEast.stats.y, "East Boundary: Y should not change");

        // --- Test Top Boundary (y=MAX_DUNGEON_Y) ---
        currentX = nad_afterEast.stats.x; // Use potentially updated X (should be MAX_DUNGEON_X)
        _teleportCharacter(charId, currentX, MAX_DUNGEON_Y);
        BattleNad memory nad_beforeNorth = _battleNad(1);
         assertEq(nad_beforeNorth.stats.y, MAX_DUNGEON_Y, "Teleport North failed");

        vm.prank(key);
        battleNads.moveNorth(charId);
        _rollForward(1);
        BattleNad memory nad_afterNorth = _battleNad(1);
        assertEq(nad_afterNorth.stats.x, nad_beforeNorth.stats.x, "North Boundary: X should not change");
        assertEq(nad_afterNorth.stats.y, nad_beforeNorth.stats.y, "North Boundary: Y should not change");
    }

    // Helper to find if a topic exists in logs (simplistic check)
    function _findLog(VmSafe.Log[] memory logs, bytes32 topic) internal pure returns (bool found) {
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                return true;
            }
        }
        return false;
    }

    // Helper to teleport character using vm.store (for boundary testing)
    function _teleportCharacter(bytes32 charId, uint8 newX, uint8 newY) internal {
        // Ensure depth is valid (assume 1 for these tests)
        BattleNad memory nad_check = battleNads.getBattleNad(charId);
        uint8 depth = nad_check.stats.depth == 0 ? 1 : nad_check.stats.depth; // Use 1 if depth is 0

        uint256 slot = 3; // Storage slot for characterStats mapping
        bytes32 statSlot = keccak256(abi.encode(charId, slot));
        uint256 packedData = uint256(vm.load(address(battleNads), statSlot));
        
        // Clear old x, y, and depth (offsets 136, 128, 144 for uint8)
        uint256 xMask = uint256(type(uint8).max) << 136;
        uint256 yMask = uint256(type(uint8).max) << 128;
        uint256 dMask = uint256(type(uint8).max) << 144;
        packedData &= (~xMask);
        packedData &= (~yMask);
        packedData &= (~dMask);

        // Set new x, y and depth
        packedData |= (uint256(newX) << 136);
        packedData |= (uint256(newY) << 128);
        packedData |= (uint256(depth) << 144);

        vm.store(address(battleNads), statSlot, bytes32(packedData));
        // No _rollForward here
    }

    // TODO: Add tests from plan.md category 3:
    // - test_Move_Invalid_Diagonal
    // - test_Move_Invalid_Jump
    // - test_Move_InCombat
    // - test_Move_AreaFull
    // - test_Move_Aggro_Existing
    // - test_Move_Aggro_Spawn
    // - test_Move_NoAggro_Level
    // - test_DepthChange_Valid
    // - test_DepthChange_InvalidCoords
    // - test_DepthChange_InvalidDepth
} 