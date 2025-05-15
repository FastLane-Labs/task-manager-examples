// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// For any shared test constants (not specific to a protocol's setup)
contract TestConstants {
    // Chain Fork Settings
    uint256 internal constant MONAD_TESTNET_FORK_BLOCK = 8_149_082;

    // AddressHub
    address internal constant TESTNET_ADDRESS_HUB = 0xC9f0cDE8316AbC5Efc8C3f5A6b571e815C021B51;

    // Task Manager
    address internal constant TESTNET_TASK_MANAGER = 0x5277C4c882BA9425E6615955b17Af34030432f27;

    // SHMONAD
    address internal constant TESTNET_SHMONAD = 0x3a98250F98Dd388C211206983453837C8365BDc1;

    address internal constant TESTNET_TASK_MANAGER_PROXY_ADMIN = 0x86780dA77e5c58f5DD3e16f58281052860f9136b;
    address internal constant TESTNET_PAYMASTER_PROXY_ADMIN = 0xc8b98327453dF25003829f220261086F39eB8899;
    address internal constant TESTNET_RPC_POLICY_PROXY_ADMIN = 0x74B1EEf0BaFA7589a1FEF3ff59996667CFCFb511;
}
