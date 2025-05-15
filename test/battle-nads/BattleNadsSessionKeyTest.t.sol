// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherit common setup and helpers
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";

// Specific imports for this test file
import { SessionKeyData } from "src/battle-nads/cashier/CashierTypes.sol";
import { console } from "forge-std/console.sol"; 

// Tests focusing on Session Key and Gas Abstraction features
contract BattleNadsSessionKeyTest is BattleNadsBaseTest {

    // Moved from original test file
    function test_UpdateAndVerifySessionKey() public {
        // 1. Define new user and session key (using user4/key4 from base)
        address newUser = user4;
        address newSessionKey = userSessionKey4;
        // vm.deal is already handled in base setUp

        // 2. Estimate cost and create character with no initial session key
        uint256 estimatedCreationCost = battleNads.estimateBuyInAmountInMON();
        vm.prank(newUser);
        bytes32 newCharacterId = battleNads.createCharacter{ value: estimatedCreationCost }(
            "SessionTester", 5, 5, 5, 5, 5, 7, address(0), 0 // Stats: str, vit, dex, qui, stu, lck (5*5 + 7 = 32)
        );
         character4 = newCharacterId; // Store the ID in the base state variable

        // Ensure creation task completes - spawn delay handled by rolling forward
        _waitForSpawn(newCharacterId);

        // 3. Update the session key
        uint64 expectedExpiration = uint64(block.timestamp + 1 hours); // Use timestamp

        // Broke down log statement
        vm.prank(newUser);
        battleNads.updateSessionKey(newSessionKey, expectedExpiration);

        // 4. Advance time slightly past the update transaction to ensure state commit
        _rollForward(1);

        // 5. Verify session key data using the view function
        SessionKeyData memory sessionKeyData_direct = battleNads.getCurrentSessionKeyData(newUser);

        // Assertions
        assertEq(sessionKeyData_direct.owner, newUser, "Session key data: owner mismatch");
        assertEq(sessionKeyData_direct.key, newSessionKey, "Session key data: key address mismatch");
        // Expiration might be off by a block or two due to rollForward, use approximate check
        assertTrue(sessionKeyData_direct.expiration >= expectedExpiration && sessionKeyData_direct.expiration < expectedExpiration + 10, "Session key data: expiration mismatch");
    }

    // TODO: Add more tests from plan.md category 6:
    // - test_SessionKey_Funding_DirectETH
    // - test_SessionKey_Funding_FromBonded
    // - test_SessionKey_Deactivate_ByOwner
    // - test_SessionKey_Deactivate_ByKey
    // - test_SessionKey_Expiration
    // - test_GasAbstracted_Action_Success
    // - test_GasAbstracted_Action_RevertHandling
    // - test_GasAbstracted_KeyBalanceDepletion
    // - test_GasAbstracted_OwnerBondedDepletion
    // - test_CreateOrUpdateSessionKey_Modifier_InCreateCharacter
} 