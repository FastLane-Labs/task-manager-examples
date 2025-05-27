//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

import { IAddressHub } from "@fastlane-contracts/common/IAddressHub.sol";
import { Directory } from "@fastlane-contracts/common/Directory.sol";
import { ITaskManager } from "@fastlane-contracts/task-manager/interfaces/ITaskManager.sol";

/**
 * @title ExecuteTasksScript
 * @notice Script to execute tasks on the TaskManager
 * @dev This script retrieves the TaskManager from AddressHub and calls executeTasks with a fixed gas limit
 */
contract ExecuteTasksScript is Script {
    // Fixed gas limit for execution (1 million)
    uint256 constant EXECUTION_GAS_LIMIT = 1_000_000;

    // Target gas to reserve after execution (50k)
    uint256 constant TARGET_GAS_RESERVE = 50_000;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address addressHub = vm.envAddress("ADDRESS_HUB");

        // Get the AddressHub instance
        IAddressHub hub = IAddressHub(addressHub);

        // Get TaskManager proxy address from AddressHub
        address taskManagerAddress = hub.getAddressFromPointer(Directory._TASK_MANAGER);
        require(taskManagerAddress != address(0), "TaskManager address not set in AddressHub");

        console.log("Starting Task execution...");
        console.log("Executor address:", deployer);
        console.log("AddressHub address:", addressHub);
        console.log("TaskManager address:", taskManagerAddress);
        console.log("Gas limit:", EXECUTION_GAS_LIMIT);
        console.log("Target gas reserve:", TARGET_GAS_RESERVE);

        // Get TaskManager instance
        ITaskManager taskManager = ITaskManager(taskManagerAddress);

        uint256 initialGas = gasleft();
        console.log("Initial gas:", initialGas);

        vm.startBroadcast(deployerPrivateKey);

        // Set a block gas limit for script execution
        vm.txGasPrice(1);

        // Execute tasks with the executor's address as payout
        uint256 feesEarned;
        bool success = false;
        string memory errorReason = "";

        try taskManager.executeTasks(deployer, TARGET_GAS_RESERVE) returns (uint256 _feesEarned) {
            feesEarned = _feesEarned;
            success = true;
            console.log("Tasks executed successfully!");
            console.log("Fees earned:", feesEarned, "wei");
        } catch Error(string memory reason) {
            errorReason = reason;
            console.log("Execution failed with reason:", reason);
        } catch (bytes memory lowLevelData) {
            errorReason = "low level error";
            console.log("Execution failed with low level error");
        }

        vm.stopBroadcast();

        uint256 gasUsed = initialGas - gasleft();
        console.log("Gas used:", gasUsed);

        console.log("\n=== Execution Report ===");
        console.log("Network:", block.chainid);
        console.log("Block number:", block.number);
        console.log("Executor address:", deployer);

        if (success) {
            console.log("\n=== EXECUTION SUCCESSFUL ===");
            console.log("FEES EARNED: %s wei", feesEarned);
            if (feesEarned > 0) {
                console.log("FEES EARNED: %s ether", feesEarned / 1e18);
            }
        } else {
            console.log("\n=== EXECUTION FAILED ===");
            console.log("Error reason: %s", errorReason);
        }
    }
}
