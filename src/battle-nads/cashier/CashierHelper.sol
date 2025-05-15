//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { ITaskManager } from "@fastlane-task-manager/src/interfaces/ITaskManager.sol";
import { IShMonad } from "../../interfaces/shmonad/IShMonad.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";

import { SessionKey, SessionKeyData, GasAbstractionTracker } from "./CashierTypes.sol";

interface ITaskManagerImmutables {
    function POLICY_ID() external view returns (uint64);
}

import { console } from "forge-std/console.sol";

// These are the entrypoint functions called by the tasks
contract CashierHelper {
    address public immutable TASK_MANAGER;
    uint64 public immutable TASK_MANAGER_POLICY_ID;
    address public immutable SHMONAD;
    uint64 public immutable POLICY_ID;
    address public immutable POLICY_WRAPPER;

    uint256 internal immutable _MAX_EXPECTED_GAS_USAGE_PER_TX;

    bytes32 private immutable SESSION_KEY_NAMESPACE;
    bytes32 private immutable KEY_OWNER_NAMESPACE;
    bytes32 private immutable ABSTRACTED_CALLER_NAMESPACE;

    uint256 internal constant _MIN_TASK_EXECUTION_GAS = 110_000;
    uint256 internal constant _TASK_MANAGER_EXECUTION_GAS_BUFFER = 31_000;
    uint256 internal constant _GAS_ABSTRACTION_MIN_REMAINDER_GAS = 65_000;
    uint256 internal constant _MIN_REMAINDER_GAS_BUFFER = 31_000;
    uint256 internal constant _BASE_TX_GAS_USAGE = 21_000;

    uint256 internal constant _BASE_FEE_MAX_INCREASE = 1125;
    uint256 internal constant _BASE_FEE_DENOMINATOR = 1000;

    bytes32 private constant _IN_USE_BIT = 0x0000000000000000000000020000000000000000000000000000000000000000;
    bytes32 private constant _IS_SESSION_KEY_BIT = 0x0000000000000000000000040000000000000000000000000000000000000000;
    bytes32 private constant _IN_USE_AS_SESSION_KEY_BITS =
        0x0000000000000000000000060000000000000000000000000000000000000000;

    event SessionKeyRemoved(
        address sessionKeyAddress,
        address indexed owner,
        address indexed applicationEntrypoint,
        uint256 remainingBalance
    );

    error InvalidSessionKeyOwner();
    error SessionKeyCantOwnSelf();
    error SessionKeyExpirationInvalid(uint256 expiration);
    error SessionKeyExpired(uint256 expiration, uint256 currentBlock);
    error MustHaveMsgValue();
    error Reentrancy();
    error UnknownMsgSender();

    constructor(address taskManager, address shMonad, uint256 maxExpectedGasUsagePerTx) {
        TASK_MANAGER = taskManager;
        SHMONAD = shMonad;

        TASK_MANAGER_POLICY_ID = ITaskManagerImmutables(taskManager).POLICY_ID();

        // Create ShMONAD commitment policy for this app
        (uint64 policyID, address policyERC20Wrapper) = IShMonad(shMonad).createPolicy(uint48(16));
        POLICY_ID = policyID;
        POLICY_WRAPPER = policyERC20Wrapper;

        _MAX_EXPECTED_GAS_USAGE_PER_TX = maxExpectedGasUsagePerTx;

        // Create storage namespaces
        SESSION_KEY_NAMESPACE = keccak256(
            abi.encode(
                "ShMONAD Gas Abstraction 1.0",
                "Session Key Namespace",
                taskManager,
                shMonad,
                policyID,
                address(this),
                block.chainid
            )
        );
        KEY_OWNER_NAMESPACE = keccak256(
            abi.encode(
                "ShMONAD Gas Abstraction 1.0",
                "Key Owner Namespace",
                taskManager,
                shMonad,
                policyID,
                address(this),
                block.chainid
            )
        );
        ABSTRACTED_CALLER_NAMESPACE = keccak256(
            abi.encode(
                "ShMONAD Gas Abstraction 1.0",
                "Abstracted Caller Transient Namespace",
                taskManager,
                shMonad,
                policyID,
                address(this),
                block.chainid
            )
        );
    }

    function _sessionKeyBalanceDeficit(address account) internal view returns (uint256 deficit) {
        if (account == address(0)) {
            // Be careful not to show the burned MON balance of the zero address
            return 0;
        }
        uint256 targetBalance = _targetSessionKeyBalance();
        uint256 currentBalance = address(account).balance;
        if (targetBalance > currentBalance) {
            return targetBalance - currentBalance;
        }
        return 0;
    }

    function _targetSessionKeyBalance() internal view returns (uint256 targetBalance) {
        uint256 gasRate = tx.gasprice > block.basefee ? tx.gasprice : block.basefee;
        gasRate = gasRate * _BASE_FEE_MAX_INCREASE / _BASE_FEE_DENOMINATOR;
        // TODO: Handle 1559-like base fee movements once monad tx fees are finalized
        targetBalance = _MAX_EXPECTED_GAS_USAGE_PER_TX * gasRate * 2;
    }

    // Can double as a reentrancy check
    function _inUse() internal view returns (bool inUse) {
        // NOTE: We use transient storage so that apps can access this value inside of a try/catch,
        // which is a useful pattern if they still want to handle the gas reimbursement of a gas abstracted
        // transaction in scenarios in which the users' call would revert.
        bytes32 abstractedCallerTransientSlot = ABSTRACTED_CALLER_NAMESPACE;
        bytes32 packedAbstractedCaller;
        assembly {
            packedAbstractedCaller := tload(abstractedCallerTransientSlot)
        }
        inUse = packedAbstractedCaller & _IN_USE_BIT != 0;
    }

    function _checkForReentrancy() internal view {
        if (_inUse()) {
            revert Reentrancy();
        }
    }

    function _lock() internal {
        bytes32 abstractedCallerTransientSlot = ABSTRACTED_CALLER_NAMESPACE;
        assembly {
            tstore(abstractedCallerTransientSlot, _IN_USE_BIT)
        }
    }

    function _loadAbstractedMsgSenderData()
        internal
        view
        returns (address abstractedMsgSender, bool isSessionKey, bool inUse)
    {
        bytes32 abstractedCallerTransientSlot = ABSTRACTED_CALLER_NAMESPACE;
        bytes32 packedAbstractedCaller;
        assembly {
            packedAbstractedCaller := tload(abstractedCallerTransientSlot)
            abstractedMsgSender :=
                and(packedAbstractedCaller, 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
        }
        isSessionKey = packedAbstractedCaller & _IS_SESSION_KEY_BIT != 0;
        inUse = packedAbstractedCaller & _IN_USE_BIT != 0;
    }

    function _storeAbstractedMsgSender(address abstractedMsgSender, bool isSessionKey) internal {
        bytes32 abstractedCallerTransientSlot = ABSTRACTED_CALLER_NAMESPACE;
        bytes32 packedAbstractedCaller = isSessionKey ? _IN_USE_AS_SESSION_KEY_BITS : _IN_USE_BIT;
        assembly {
            tstore(abstractedCallerTransientSlot, or(packedAbstractedCaller, abstractedMsgSender))
        }
    }

    function _clearAbstractedMsgSender() internal {
        bytes32 abstractedCallerTransientSlot = ABSTRACTED_CALLER_NAMESPACE;
        assembly {
            tstore(abstractedCallerTransientSlot, 0x0000000000000000000000000000000000000000000000000000000000000000)
        }
    }

    function _updateSessionKey(address sessionKeyAddress, address owner, uint256 expiration) internal {
        if (sessionKeyAddress == owner) {
            revert SessionKeyCantOwnSelf();
        }
        if (expiration > type(uint64).max) {
            revert SessionKeyExpirationInvalid(expiration);
        }

        address existingSessionKeyAddress;
        bytes32 keyOwnerStorageSlot = keccak256(abi.encodePacked(owner, KEY_OWNER_NAMESPACE));
        assembly {
            existingSessionKeyAddress := sload(keyOwnerStorageSlot)
        }

        // Deactivate existing session key if it exists and then point the owner at the new session key address
        if (sessionKeyAddress != existingSessionKeyAddress) {
            if (existingSessionKeyAddress != address(0)) {
                _deactivateSessionKey(existingSessionKeyAddress);
            }
            assembly {
                // Update owner->key mapping
                // NOTE: This should still update even if we're setting a sessionKeyAddress of zero,
                // which has the same effect as deleting the old sessionKeyAddress
                sstore(keyOwnerStorageSlot, sessionKeyAddress)
            }
        }

        // Update the session key mapping as long as the new session key isn't the zero address
        if (sessionKeyAddress != address(0)) {
            bytes32 sessionKeyStorageSlot = keccak256(abi.encodePacked(sessionKeyAddress, SESSION_KEY_NAMESPACE));
            assembly {
                let packedSessionKey := or(owner, shl(192, expiration))
                sstore(sessionKeyStorageSlot, packedSessionKey)
            }
        }
    }

    function _deactivateSessionKey(address sessionKeyAddress) internal {
        // Set to expired, but keep 'owner' parameter
        bytes32 sessionKeyStorageSlot = keccak256(abi.encodePacked(sessionKeyAddress, SESSION_KEY_NAMESPACE));
        uint256 expiration;
        bytes32 packedSessionKey;
        assembly {
            packedSessionKey := sload(sessionKeyStorageSlot)
            expiration :=
                and(shr(192, packedSessionKey), 0x000000000000000000000000000000000000000000000000ffffffffffffffff)
        }
        // Only write to storage if the sessionKey isn't expired
        if (expiration > 0) {
            address owner;
            assembly {
                // Clean the expiration, keep the rest
                sstore(
                    sessionKeyStorageSlot,
                    and(packedSessionKey, 0x0000000000000000ffffffffffffffffffffffffffffffffffffffffffffffff)
                )

                // Get owner for event emission
                owner := and(packedSessionKey, 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
            }

            // Emit balance event to help apps track any lingering balances
            emit SessionKeyRemoved(sessionKeyAddress, owner, address(this), address(sessionKeyAddress).balance);
        }
    }

    function _getSessionKeyAddress(address ownerAddress) internal view returns (address sessionKeyAddress) {
        bytes32 keyOwnerStorageSlot = keccak256(abi.encodePacked(ownerAddress, KEY_OWNER_NAMESPACE));
        assembly {
            sessionKeyAddress := sload(keyOwnerStorageSlot)
        }
    }

    function _loadSessionKey(address sessionKeyAddress) internal view returns (SessionKey memory sessionKey) {
        bytes32 sessionKeyStorageSlot = keccak256(abi.encodePacked(sessionKeyAddress, SESSION_KEY_NAMESPACE));
        address owner;
        uint256 expiration;
        assembly {
            let packedSessionKey := sload(sessionKeyStorageSlot)
            owner := and(packedSessionKey, 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff)
            expiration :=
                and(shr(192, packedSessionKey), 0x000000000000000000000000000000000000000000000000ffffffffffffffff)
        }
        sessionKey.owner = owner;
        sessionKey.expiration = uint64(expiration);
    }

    function _loadSessionKeyFromOwner(address ownerAddress) internal view returns (SessionKey memory sessionKey) {
        address sessionKeyAddress = _getSessionKeyAddress(ownerAddress);

        if (sessionKeyAddress != address(0)) {
            sessionKey = _loadSessionKey(sessionKeyAddress);
        }
    }

    function _creditToOwnerAndBond(address owner, uint256 shares) internal {
        // Deposit and bond to owner's BATTLE-NADS policy
        IShMonad(SHMONAD).bond(POLICY_ID, owner, shares);
    }

    function _takeFromOwnerBondedShares(address owner, uint256 shares) internal {
        IShMonad(SHMONAD).agentTransferToUnbonded(POLICY_ID, owner, address(this), shares, 0, false);
    }

    function _takeFromOwnerBondedAmount(address owner, uint256 amount) internal {
        IShMonad(SHMONAD).agentTransferToUnbonded(POLICY_ID, owner, address(this), amount, 0, true);
    }

    function _takeFromOwnerBondedAmountInUnderlying(address owner, uint256 amount) internal {
        IShMonad(SHMONAD).agentWithdrawFromBonded(POLICY_ID, owner, address(this), amount, 0, true);
    }

    function _bondSharesToTaskManager(uint256 shares) internal {
        // This contract owns all tasks
        IShMonad(SHMONAD).bond(TASK_MANAGER_POLICY_ID, address(this), shares);
    }

    function _bondAmountToTaskManager(uint256 amount) internal {
        // This contract owns all tasks
        IShMonad(SHMONAD).depositAndBond{ value: amount }(TASK_MANAGER_POLICY_ID, address(this), type(uint256).max);
    }

    function _beginUnbondFromTaskManager(uint256 shares) internal {
        // This contract owns all tasks
        IShMonad(SHMONAD).unbond(TASK_MANAGER_POLICY_ID, shares, 0);
    }

    function _taskManagerUnbondingBlock() internal view returns (uint256 blockNumber) {
        // This contract owns all tasks
        blockNumber = IShMonad(SHMONAD).unbondingCompleteBlock(TASK_MANAGER_POLICY_ID, address(this));
    }

    function _completeUnbondFromTaskManager(uint256 shares) internal {
        // This contract owns all tasks
        IShMonad(SHMONAD).claim(TASK_MANAGER_POLICY_ID, shares);
    }

    function _sharesBondedToTaskManager(address owner) internal view returns (uint256 shares) {
        shares = IShMonad(SHMONAD).balanceOfBonded(TASK_MANAGER_POLICY_ID, owner);
    }

    function _sharesUnbondingFromTaskManager(address owner) internal view returns (uint256 shares) {
        shares = IShMonad(SHMONAD).balanceOfUnbonding(TASK_MANAGER_POLICY_ID, owner);
    }

    function _sharesBondedToThis(address owner) internal view returns (uint256 shares) {
        shares = IShMonad(SHMONAD).balanceOfBonded(POLICY_ID, owner);
    }

    function _amountBondedToThis(address owner) internal view returns (uint256 amount) {
        // TODO: Boost gas efficiency by adding a combo function into shMonad
        amount = IShMonad(SHMONAD).convertToAssets(IShMonad(SHMONAD).balanceOfBonded(POLICY_ID, owner));
    }

    function _sharesUnbondingFromThis(address owner) internal view returns (uint256 shares) {
        shares = IShMonad(SHMONAD).balanceOfUnbonding(POLICY_ID, owner);
    }

    function _boostYieldShares(uint256 shares) internal {
        IShMonad(SHMONAD).boostYield(shares, address(this));
    }

    function _boostYieldAmount(uint256 amount) internal {
        IShMonad(SHMONAD).boostYield{ value: amount }();
    }

    function _convertMonToShMon(uint256 amount) internal view returns (uint256 shares) {
        shares = IShMonad(SHMONAD).convertToShares(amount);
    }

    function _convertShMonToMon(uint256 shares) internal view returns (uint256 amount) {
        amount = IShMonad(SHMONAD).convertToAssets(shares);
    }

    function _depositMonAndBondForRecipient(address bondRecipient, uint256 amount) internal {
        IShMonad(SHMONAD).depositAndBond{ value: amount }(POLICY_ID, bondRecipient, type(uint256).max);
    }

    function _estimateTaskCost(uint256 targetBlock, uint256 maxTaskGas) internal view returns (uint256 cost) {
        // Cost is in MON
        cost = ITaskManager(TASK_MANAGER).estimateCost(uint64(targetBlock), maxTaskGas);
    }
}
