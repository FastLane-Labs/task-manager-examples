//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "src/battle-nads/Entrypoint.sol";
import "src/battle-nads/Types.sol";

contract GetTaskSchedule is Script {
    BattleNadsEntrypoint public battleNads;

    function setUp() public {
        battleNads = BattleNadsEntrypoint(payable(0x25DbB5AcC6e3AC7E51Cb803a2DB2d9F25828F995));
    }

    function run() public {
        // Use the character from the trace
        bytes32 characterId = 0xa9b45c54c4505776e054cbb6ce7cb4e54462e7859ccc349ac6199bd6dcde5fc0;

        console.log("=== Testing Active Ability Detection ===");
        console.log("Character ID: ", vm.toString(characterId));

        // Check initial state
        BattleNad memory initialChar = battleNads.getBattleNad(characterId);
        console.log("Initial ability state:", uint256(initialChar.activeAbility.ability));
        console.log("Initial task address:", initialChar.activeAbility.taskAddress);

        // If already has active ability, monitor it
        if (initialChar.activeAbility.taskAddress != address(0) && initialChar.activeAbility.taskAddress != address(1))
        {
            console.log("=== FOUND ACTIVE ABILITY! ===");
            console.log("Ability Type:", uint256(initialChar.activeAbility.ability));
            console.log("Stage:", uint256(initialChar.activeAbility.stage));
            console.log("Target Block:", uint256(initialChar.activeAbility.targetBlock));
            console.log("Current Block:", block.number);

            // Monitor the ability through its execution
            _monitorAbilityExecution(characterId, initialChar.activeAbility.targetBlock);
        } else {
            console.log("No active ability found, trying to trigger one...");

            // Check if character is in combat (needed for abilities)
            if (initialChar.stats.combatants > 0) {
                console.log("Character is in combat, attempting to use ability...");
                _attemptAbilityUsage(characterId);
            } else {
                console.log("Character not in combat - abilities require combat");
                console.log("Combatants:", uint256(initialChar.stats.combatants));
            }
        }

        // Final state check
        BattleNad memory finalChar = battleNads.getBattleNad(characterId);
        console.log("=== Final State ===");
        console.log("Ability:", uint256(finalChar.activeAbility.ability));
        console.log("Task Address:", finalChar.activeAbility.taskAddress);
        console.log("UpdateActiveAbility flag:", finalChar.tracker.updateActiveAbility);
    }

    function _monitorAbilityExecution(bytes32 characterId, uint256 targetBlock) internal {
        console.log("=== Monitoring Ability Execution ===");

        // Poll every block until target block
        for (uint256 i = 0; i < 10; i++) {
            BattleNad memory char = battleNads.getBattleNad(characterId);

            console.log("Block", block.number, "- Ability:", uint256(char.activeAbility.ability));
            console.log("Block", block.number, "- Stage:", uint256(char.activeAbility.stage));
            console.log("Block", block.number, "- Task Addr:", char.activeAbility.taskAddress);
            console.log("Block", block.number, "- Update Flag:", char.tracker.updateActiveAbility);

            // Check if ability completed
            if (char.activeAbility.taskAddress == address(1)) {
                console.log("*** ABILITY COMPLETED AT BLOCK", block.number, "***");
                break;
            }

            // Check if we reached target block
            if (block.number >= targetBlock) {
                console.log("*** REACHED TARGET BLOCK", targetBlock, "***");
                // Roll forward one more to see execution result
                vm.roll(block.number + 1);
                char = battleNads.getBattleNad(characterId);
                console.log("Post-execution - Ability:", uint256(char.activeAbility.ability));
                console.log("Post-execution - Task Addr:", char.activeAbility.taskAddress);
                break;
            }

            // Advance to next block
            vm.roll(block.number + 1);
        }
    }

    function _attemptAbilityUsage(bytes32 characterId) internal {
        // This would require proper session key setup and combat state
        // For now, just document what we'd need to do
        console.log("To test active abilities, we would need:");
        console.log("1. Valid session key for the character owner");
        console.log("2. Character in combat state");
        console.log("3. Call battleNads.useAbility() with proper parameters");
        console.log("4. Poll immediately after to catch active state");

        // Show current combat state
        BattleNad memory char = battleNads.getBattleNad(characterId);
        console.log("Combat info:");
        console.log("- Combatants:", uint256(char.stats.combatants));
        console.log("- Combat bitmap:", uint256(char.stats.combatantBitMap));
        console.log("- Next target:", uint256(char.stats.nextTargetIndex));
    }
}
