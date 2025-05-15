// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { Getters } from "../../src/task-manager/examples/battle-nads/Getters.sol";

contract GetCharacterIDScript is Script {
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

        console.log("Fetching character ID for owner:", ownerAddress);

        // Instantiate the Getters contract interface
        Getters getters = Getters(gettersAddress);

        // Call the view function to get the character ID
        vm.startBroadcast();
        bytes32 characterID = getters.getPlayerCharacterID(ownerAddress);
        vm.stopBroadcast();

        // Log the retrieved character ID
        console.log("Character ID found:", vm.toString(characterID));
    }
}
