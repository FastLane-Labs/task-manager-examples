// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { Getters } from "../../src/battle-nads/Getters.sol";
import { SessionKeyData } from "lib/fastlane-contracts/src/common/relay/GasRelayTypes.sol";
import { BattleNad, BattleNadLite, DataFeed } from "../../src/battle-nads/Types.sol";

contract GetSessionKeyDataScript is Script {
    uint256 BLOCK_OFFSET = 1;

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

    /**
     * @notice Get the owner address from environment
     * @return The address of the owner
     */
    function getOwnerAddress() internal view returns (address) {
        // Get from environment variable
        try vm.envAddress("OWNER_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                console.log("Using owner address from environment: %s", addr);
                return addr;
            }
            revert("OWNER_ADDRESS is set to zero address");
        } catch {
            revert("OWNER_ADDRESS environment variable is required");
        }
    }

    function run() public view {
        // Get the Getters contract address
        address gettersAddress = getDeployedGettersAddress();
        console.log("Using Getters contract at:", gettersAddress);

        // Get Owner address from environment
        address ownerAddress = getOwnerAddress();
        console.log("Fetching Session Key Data for owner:", ownerAddress);

        // Instantiate the Getters contract interface
        Getters getters = Getters(gettersAddress);

        // Call pollForFrontendData to retrieve sessionKeyData
        // WARNING: This function is complex and potentially gas-intensive.
        // Use startBlock = 0 as we only need the session key data part.
        // We need to declare all return variables even if we don't use them all.
        bytes32 characterID;
        SessionKeyData memory sessionKeyData;
        BattleNad memory character; // Note: Allocates memory
        BattleNadLite[] memory combatants; // Note: Allocates memory
        BattleNadLite[] memory noncombatants; // Note: Allocates memory
        uint8[] memory equipableWeaponIDs;
        string[] memory equipableWeaponNames;
        uint8[] memory equipableArmorIDs;
        string[] memory equipableArmorNames;
        DataFeed[] memory dataFeeds;
        uint256 balanceShortfall;
        uint256 unallocatedAttributePoints;
        uint256 endBlock;

        (
            characterID,
            sessionKeyData,
            character,
            combatants,
            noncombatants,
            equipableWeaponIDs,
            equipableWeaponNames,
            equipableArmorIDs,
            equipableArmorNames,
            dataFeeds,
            balanceShortfall,
            unallocatedAttributePoints,
            endBlock
        ) = getters.pollForFrontendData(ownerAddress, block.number - BLOCK_OFFSET);

        // Log the retrieved session key data
        console.log("--- Session Key Data ---");
        console.log("Key Address:      ", sessionKeyData.key);
        console.log("Expiration Block: ", sessionKeyData.expiration);
        console.log("------------------------");
    }
}
