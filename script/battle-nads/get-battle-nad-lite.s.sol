// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { Getters } from "../../src/battle-nads/Getters.sol";
import { BattleNadLite } from "../../src/battle-nads/Types.sol";

contract GetBattleNadLiteScript is Script {
    /**
     * @notice Get the Getters contract address from environment
     * @return The address of the BattleNads Getters contract
     */
    function getDeployedGettersAddress() internal view returns (address) {
        // Get from environment variable
        try vm.envAddress("GETTERS_CONTRACT_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                console.log("Using Getters contract address from environment: %s", addr);
                return addr;
            }
            revert("GETTERS_CONTRACT_ADDRESS is set to zero address");
        } catch {
            revert("GETTERS_CONTRACT_ADDRESS environment variable is required");
        }
    }

    function run(address ownerAddress) public {
        // Get the Getters contract address
        address gettersAddress = getDeployedGettersAddress();
        console.log("Using Getters contract at:", gettersAddress);

        console.log("Fetching BattleNadLite data for owner:", ownerAddress);

        // Instantiate the Getters contract interface
        Getters getters = Getters(gettersAddress);

        // First get the character ID for this owner
        vm.startBroadcast();
        bytes32 characterID = getters.getPlayerCharacterID(ownerAddress);

        if (characterID == bytes32(0)) {
            console.log("No character found for this owner");
            vm.stopBroadcast();
            return;
        }

        console.log("Character ID found:", vm.toString(characterID));

        // Now get the BattleNadLite data
        BattleNadLite memory character = getters.getBattleNadLite(characterID);
        vm.stopBroadcast();

        _logBattleNadLiteData(character);
    }

    // Overloaded function to accept character ID directly
    function run(bytes32 characterID) public {
        // Get the Getters contract address
        address gettersAddress = getDeployedGettersAddress();
        console.log("Using Getters contract at:", gettersAddress);

        console.log("Fetching BattleNadLite data for character ID:", vm.toString(characterID));

        // Instantiate the Getters contract interface
        Getters getters = Getters(gettersAddress);

        // Get the BattleNadLite data directly
        vm.startBroadcast();
        BattleNadLite memory character = getters.getBattleNadLite(characterID);
        vm.stopBroadcast();

        _logBattleNadLiteData(character);
    }

    // Helper function to log BattleNadLite data
    function _logBattleNadLiteData(BattleNadLite memory character) internal pure {
        // Log the retrieved BattleNadLite data
        console.log("=== BattleNadLite Data ===");
        console.log("ID:           ", vm.toString(character.id));
        console.log("Name:         ", character.name);
        console.log("Class:        ", uint256(character.class));
        console.log("Level:        ", character.level);
        console.log("Health:       ", character.health);
        console.log("Max Health:   ", character.maxHealth);
        console.log("Index:        ", character.index);
        console.log("Is Dead:      ", character.isDead ? "Yes" : "No");
        console.log("Buffs:        ", character.buffs);
        console.log("Debuffs:      ", character.debuffs);
        console.log("Combatant Map:", character.combatantBitMap);

        // Ability information
        console.log("--- Ability Info ---");
        console.log("Ability:      ", uint256(character.ability));
        console.log("Ability Stage:", character.abilityStage);
        console.log("Target Block: ", character.abilityTargetBlock);
        console.log("------------------");

        // Equipment information (only names available in BattleNadLite)
        console.log("--- Equipment ---");
        console.log("Weapon Name:  ", character.weaponName);
        console.log("Armor Name:   ", character.armorName);
        console.log("================");
    }
}
