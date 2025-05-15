// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Test } from "forge-std/Test.sol";
import { TestConstants } from "test/TestConstants.sol";
import { ITaskManager } from "@fastlane-task-manager/src/interfaces/ITaskManager.sol";

contract BaseTest is TestConstants, Test {
    string internal networkRpcUrl = "MONAD_TESTNET_RPC_URL";
    uint256 internal forkBlock = MONAD_TESTNET_FORK_BLOCK;

    ITaskManager public immutable taskManager = ITaskManager(TESTNET_TASK_MANAGER);
    address public immutable shMonad = TESTNET_SHMONAD;

    function setUp() public virtual {
        _configureNetwork();
        if (forkBlock != 0) {
            vm.createSelectFork(vm.envString(networkRpcUrl), forkBlock);
        } else {
            vm.createSelectFork(vm.envString(networkRpcUrl));
        }
    }

    function _configureNetwork() internal virtual {
        // Default configuration is mainnet
        networkRpcUrl = "MONAD_TESTNET_RPC_URL";
        forkBlock = 0; // 0 means latest block
    }
}
