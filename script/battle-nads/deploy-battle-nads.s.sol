// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { BattleNadsEntrypoint } from "../../src/battle-nads/Entrypoint.sol";
import { BattleNadsImplementation } from "../../src/battle-nads/tasks/BattleNadsImplementation.sol";

contract DeployBattleNads is Script {
    // Deployment addresses will be stored here
    struct DeploymentAddresses {
        address taskManager;
        address shMonad;
        address entrypoint;
        uint64 policyID;
        address policyERC20Wrapper;
    }

    // Add environment variables support
    function getEnvAddress(string memory envName) internal returns (address) {
        try vm.envAddress(envName) returns (address addr) {
            if (addr == address(0)) {
                console.log("Warning: %s is set to zero address", envName);
            }
            return addr;
        } catch {
            console.log("Environment variable %s not set or invalid", envName);
            revert(string.concat("Missing or invalid address: ", envName));
        }
    }

    function checkNetwork() internal view {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        if (chainId == 10_143) {
            console.log("Network: Monad Testnet (Chain ID: 10143)");
        } else if (chainId == 1337 || chainId == 31_337) {
            console.log("Network: Local Development Network (Chain ID: %s)", chainId);
        } else {
            console.log("Network: Unknown (Chain ID: %s)", chainId);
            console.log("Make sure you're deploying to the correct network");
        }
    }

    function run() public returns (DeploymentAddresses memory addresses) {
        // Check network before starting
        checkNetwork();

        // Read private key from environment
        uint256 deployerPrivateKey;
        address deployer;

        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
            deployer = vm.addr(deployerPrivateKey);
            console.log("Deployer address:", deployer);
        } catch {
            console.log("PRIVATE_KEY environment variable not set or invalid");
            revert("Missing or invalid PRIVATE_KEY");
        }

        // Get AddressHub address from environment
        address addressHubAddress = getEnvAddress("ADDRESS_HUB");
        console.log("AddressHub address:", addressHubAddress);

        // Get the AddressHub instance
        AddressHub hub = AddressHub(addressHubAddress);

        // Get TaskManager proxy address from AddressHub
        address taskManager = hub.getAddressFromPointer(Directory._TASK_MANAGER);
        require(taskManager != address(0), "TaskManager address not set in AddressHub");

        // Get shMONAD address from AddressHub
        address shMonad = hub.getAddressFromPointer(Directory._SHMONAD);
        require(shMonad != address(0), "shMONAD address not set in AddressHub");

        console.log("Task Manager address from AddressHub:", taskManager);
        console.log("ShMonad address from AddressHub:", shMonad);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy BattleNadsEntrypoint
        // The constructor handles everything including:
        // - Deploying BattleNadsImplementation
        // - Creating required policies
        console.log("Deploying BattleNadsEntrypoint...");
        BattleNadsEntrypoint entrypoint = new BattleNadsEntrypoint(taskManager, shMonad);

        address taskImplementation = entrypoint.TASK_IMPLEMENTATION();
        uint64 policyID = entrypoint.POLICY_ID();
        address policyERC20Wrapper = entrypoint.POLICY_WRAPPER();

        console.log("BattleNadsEntrypoint deployed at:", address(entrypoint));
        console.log("BattleNadsTaskImplementation deployed at:", taskImplementation);
        console.log("Policy created with ID:", policyID);
        console.log("Policy ERC20 wrapper address:", policyERC20Wrapper);

        vm.stopBroadcast();

        // Store deployment addresses
        addresses = DeploymentAddresses({
            taskManager: taskManager,
            shMonad: shMonad,
            entrypoint: address(entrypoint),
            policyID: policyID,
            policyERC20Wrapper: policyERC20Wrapper
        });

        // Output deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("BattleNadsEntrypoint: %s", address(entrypoint));
        console.log("BattleNadsTaskImplementation: %s", taskImplementation);
        console.log("Policy ID: %s", policyID);
        console.log("Policy ERC20 Wrapper: %s", policyERC20Wrapper);

        return addresses;
    }
}
