//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

struct SessionKey {
    address owner;
    uint64 expiration; // block number
}

struct SessionKeyData {
    address owner;
    address key;
    uint256 balance; // In MON
    uint256 targetBalance; // In MON
    uint256 ownerCommittedAmount; // In MON
    uint256 ownerCommittedShares; // In shMON
    uint64 expiration; // block number
}

struct GasAbstractionTracker {
    bool usingSessionKey;
    address owner;
    address key;
    uint64 expiration; // block number
    uint256 startingGasLeft;
    uint256 credits; // in shMON
}
