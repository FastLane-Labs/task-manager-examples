//SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import { ITaskManager } from "../../../interfaces/ITaskManager.sol";
import { IShMonad } from "../../interfaces/shmonad/IShMonad.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { SessionKey, SessionKeyData, GasAbstractionTracker } from "./CashierTypes.sol";
import { CashierHelper } from "./CashierHelper.sol";
import "./CashierErrors.sol";

// These are the entrypoint functions called by the tasks
contract Cashier is CashierHelper {
    constructor(
        address taskManager,
        address shMonad,
        uint256 maxExpectedGasUsagePerTx
    )
        CashierHelper(taskManager, shMonad, maxExpectedGasUsagePerTx)
    { }

    function getCurrentSessionKeyData(address owner) public view returns (SessionKeyData memory sessionKeyData) {
        if (owner == address(0)) {
            return sessionKeyData;
        }

        sessionKeyData.owner = owner;
        sessionKeyData.ownerCommittedShares = _sharesBondedToThis(owner);
        sessionKeyData.ownerCommittedAmount = _convertShMonToMon(sessionKeyData.ownerCommittedShares);
        if (sessionKeyData.ownerCommittedAmount > 0) --sessionKeyData.ownerCommittedAmount; // Rounding

        address key = _getSessionKeyAddress(sessionKeyData.owner);
        sessionKeyData.targetBalance = _targetSessionKeyBalance();

        if (key == address(0)) {
            return sessionKeyData;
        }

        sessionKeyData.key = key;
        sessionKeyData.balance = address(key).balance;
        sessionKeyData.expiration = _loadSessionKey(key).expiration;

        return sessionKeyData;
    }

    // NOTE: Set sessionKeyAddress to address(0) or expiration to 0 will deactivate a session key
    // NOTE: Must be called by owner
    function updateSessionKey(address sessionKeyAddress, uint256 expiration) external payable Locked {
        _updateSessionKey(sessionKeyAddress, msg.sender, expiration);
        if (msg.value > 0 && sessionKeyAddress != address(0) && expiration > block.number) {
            uint256 depositRemaining = _handleSessionKeyFunding(msg.sender, sessionKeyAddress, msg.value);
            if (depositRemaining > 0) {
                _depositMonAndBondForRecipient(msg.sender, depositRemaining);
            }
        }
    }

    function replenishGasBalance() external payable Locked {
        if (msg.value == 0) revert MustHaveMsgValue();
        uint256 depositRemaining = msg.value;

        address sessionKeyAddress = _getSessionKeyAddress(msg.sender);
        if (sessionKeyAddress != address(0) && _loadSessionKey(sessionKeyAddress).expiration > block.number) {
            depositRemaining = _handleSessionKeyFunding(msg.sender, sessionKeyAddress, msg.value);
        }

        if (depositRemaining > 0) {
            _depositMonAndBondForRecipient(msg.sender, depositRemaining);
        }
    }

    // Can be called by either owner or the session key itself
    // NOTE: A session key can't renew or extend itself
    function deactivateSessionKey(address sessionKeyAddress) external payable Locked {
        // Validate caller
        address owner;
        if (sessionKeyAddress == msg.sender) {
            owner = _loadSessionKey(sessionKeyAddress).owner;
        } else if (sessionKeyAddress == _getSessionKeyAddress(msg.sender)) {
            owner = msg.sender;
        } else {
            revert InvalidSessionKeyOwner();
        }

        _updateSessionKey(sessionKeyAddress, owner, 0);
        if (msg.value > 0) {
            _depositMonAndBondForRecipient(owner, msg.value);
        }
    }

    // NOTE: msg.sender should be the address that owns the sessionKeyAddress, NOT the sessionKeyAddress itself.
    modifier CreateOrUpdateSessionKey(
        address sessionKeyAddress,
        address owner,
        uint256 sessionKeyExpiration,
        uint256 depositValue
    ) {
        // Check for reentrancy
        _checkForReentrancy();

        // Establish the session key
        if (
            sessionKeyAddress != address(0) && sessionKeyExpiration > block.number && owner == msg.sender
                && sessionKeyAddress != owner
        ) {
            _updateSessionKey(sessionKeyAddress, owner, sessionKeyExpiration);

            // Fill session key with gas from the depositValue:
            // NOTE: depositValue returned from _handleSessionKeyFunding is the remaining after
            // transfering the target amount to the session key address
            depositValue = _handleSessionKeyFunding(owner, sessionKeyAddress, depositValue);
        }

        // Bond any surplus depositValue to this app on behalf of msg.sender
        if (depositValue > 0) {
            _depositMonAndBondForRecipient(owner, depositValue);
        }

        // Update the _abstractedMsgSender() returned value
        _storeAbstractedMsgSender(owner, false);

        // Call the function
        _;

        // Clear msg.sender but keep the transient storage slot in 'locked' mode
        _lock();

        // Use any remaining gas to crank the task manager and reimburse the user
        if (gasleft() > _MIN_TASK_EXECUTION_GAS + _TASK_MANAGER_EXECUTION_GAS_BUFFER + _MIN_REMAINDER_GAS_BUFFER) {
            uint256 sharesEarned = ITaskManager(TASK_MANAGER).executeTasks(address(this), _MIN_REMAINDER_GAS_BUFFER);
            if (sharesEarned > 0) {
                _creditToOwnerAndBond(owner, sharesEarned);
            }
        }

        // Clear the _abstractedMsgSender() returned value
        _clearAbstractedMsgSender();
    }

    modifier GasAbstracted() {
        // Safety First
        _checkForReentrancy();

        // Check for session and start gas abstraction
        GasAbstractionTracker memory gasAbstractionTracker = _startShMonadGasAbstraction(msg.sender);

        _storeAbstractedMsgSender(gasAbstractionTracker.owner, gasAbstractionTracker.usingSessionKey);

        // Call the function
        _;

        // Clear msg.sender but keep the transient storage slot in 'locked' mode
        _lock();

        // Use any unused gas to generate credits by cranking the task manager
        gasAbstractionTracker = _handleUnusedGas(gasAbstractionTracker, _MIN_REMAINDER_GAS_BUFFER);

        // Handle session key reimbursements
        _finishShMonadGasAbstraction(gasAbstractionTracker);

        // Clear session key value and reentrancy lock
        _clearAbstractedMsgSender();
    }

    modifier Locked() {
        if (_inUse()) {
            revert Reentrancy();
        }
        _lock();

        _;

        _clearAbstractedMsgSender();
    }

    function _abstractedMsgSender() internal view virtual returns (address) {
        // NOTE: We use transient storage so that apps can access this value inside of a try/catch,
        // which is a useful pattern if they still want to handle the gas reimbursement of a gas abstracted
        // transaction in scenarios in which the users' call would revert.

        (address msgSender, bool isSessionKey, bool inUse) = _loadAbstractedMsgSenderData();

        if (isSessionKey && inUse && msgSender != address(0)) {
            return msgSender;
        }

        return msg.sender;
    }

    function _isSessionKey() internal view returns (bool isSessionKey) {
        (, isSessionKey,) = _loadAbstractedMsgSenderData();
    }

    function _handleUnusedGas(
        GasAbstractionTracker memory gasAbstractionTracker,
        uint256 minRemainderGas
    )
        internal
        returns (GasAbstractionTracker memory)
    {
        uint256 gasTarget = gasleft();
        // Make sure we have enough gas remaining for the app to finish its call
        if (gasTarget < minRemainderGas + _MIN_REMAINDER_GAS_BUFFER) {
            return gasAbstractionTracker;
        }
        gasTarget -= minRemainderGas + _MIN_REMAINDER_GAS_BUFFER;

        // Make sure the gasTarget is large enough to execute a small task
        if (gasTarget < _MIN_TASK_EXECUTION_GAS + _TASK_MANAGER_EXECUTION_GAS_BUFFER) {
            return gasAbstractionTracker;
        }

        // Call task manager to execute tasks and get reimbursed for unused gas
        if (gasAbstractionTracker.usingSessionKey) {
            gasAbstractionTracker.credits +=
                ITaskManager(TASK_MANAGER).executeTasks{ gas: gasTarget }(address(this), minRemainderGas);
        } else {
            ITaskManager(TASK_MANAGER).executeTasks{ gas: gasTarget }(msg.sender, minRemainderGas);
        }
        return gasAbstractionTracker;
    }

    function _startShMonadGasAbstraction(address caller)
        internal
        view
        returns (GasAbstractionTracker memory gasAbstractionTracker)
    {
        // NOTE: Assumes msg.sender is session key
        SessionKey memory sessionKey = _loadSessionKey(caller);
        if (sessionKey.owner != address(0) && uint64(block.number) < sessionKey.expiration) {
            gasAbstractionTracker = GasAbstractionTracker({
                usingSessionKey: true,
                owner: sessionKey.owner,
                key: caller,
                expiration: sessionKey.expiration,
                startingGasLeft: gasleft() + _BASE_TX_GAS_USAGE + (msg.data.length * 16),
                credits: 0
            });
        } else {
            gasAbstractionTracker = GasAbstractionTracker({
                usingSessionKey: false,
                owner: caller, // Beneficiary of any task execution credits
                key: address(0),
                expiration: 0,
                startingGasLeft: gasleft() + _BASE_TX_GAS_USAGE + (msg.data.length * 16),
                credits: 0
            });
        }
        return gasAbstractionTracker;
    }

    function _finishShMonadGasAbstraction(GasAbstractionTracker memory gasAbstractionTracker) internal {
        // Players gas abstract themselves with shMONAD - partial reimbursement is OK.
        // Don't do gas reimbursement if owner is caller
        // NOTE: Apps wishing to monetize shMONAD can easily build their own markup into these calculations,
        // ShMONAD is permissionless.

        // Withdraw ShMON from owner's bonded and transfer MON to msg.sender to reimburse for gas
        // NOTE: Credits typically come from executor fees from task manager crank
        // NOTE: BattleNads contract will have received credits as shmonad shares
        uint256 credits = gasAbstractionTracker.credits;

        // NOTE: We don't subtract startingGasLeft because this is MONAD - all transactions pay the
        // full gas limit (rather than execution gas used) because execution is asynchronous.
        uint256 sharesNeeded = 0;

        if (gasAbstractionTracker.usingSessionKey) {
            uint256 replacementGas = gasAbstractionTracker.startingGasLeft > _MAX_EXPECTED_GAS_USAGE_PER_TX
                ? _MAX_EXPECTED_GAS_USAGE_PER_TX
                : gasAbstractionTracker.startingGasLeft;
            uint256 replacementAmount = replacementGas * tx.gasprice;
            uint256 deficitAmount = _sessionKeyBalanceDeficit(gasAbstractionTracker.key);

            if (deficitAmount == 0) {
                sharesNeeded = 0;
            } else if (deficitAmount > replacementAmount * _BASE_FEE_MAX_INCREASE / _BASE_FEE_DENOMINATOR) {
                // TODO: This needs more bespoke handling of base fee increases - will update once
                // Monad TX fee mechanism is published.
                sharesNeeded = _convertMonToShMon(replacementAmount * _BASE_FEE_MAX_INCREASE / _BASE_FEE_DENOMINATOR);
            } else {
                sharesNeeded = _convertMonToShMon(deficitAmount);
            }
        }

        // Handle different cases - avoid overflow
        // CASE: Credits exceed or equal to reimbursement
        if (credits >= sharesNeeded) {
            // Refill the sessionKey
            if (sharesNeeded > 0) {
                // TODO: This will need to be updated to use the ClearingHouse's atomic unstaking function
                IShMonad(SHMONAD).redeem(sharesNeeded, gasAbstractionTracker.key, address(this));
                credits -= sharesNeeded;
            }

            // CASE: reimbrusement amount is less than credits received
        } else if (sharesNeeded > credits) {
            if (credits > 0) {
                // TODO: This will need to be updated to use the ClearingHouse's atomic unstaking function
                // NOTE: if gasAbstractionTracker.key is zero address, sharesNeeded would also be zero.
                IShMonad(SHMONAD).redeem(credits, gasAbstractionTracker.key, address(this));
                sharesNeeded -= credits;
            }
        }

        // CASE: Balanced
        if (credits == sharesNeeded) {
            // Return early if credits == sharesNeeded
            return;

            // CASE: More credits than shares needed & shares needed have been paid in full
        } else if (credits > sharesNeeded) {
            _creditToOwnerAndBond(gasAbstractionTracker.owner, credits);

            // CASE: Need to take remaining shares needed from commited ShMON
        } else {
            // Optimistically take from from the owner's bonded balance
            // This avoids balance check in the happy path)
            try IShMonad(SHMONAD).agentWithdrawFromBonded(
                POLICY_ID, gasAbstractionTracker.owner, gasAbstractionTracker.key, sharesNeeded, 0, false
            ) {
                // Success (owner's bonded balance sufficiently covered the gas cost)
            } catch {
                // If the owner doesn't have enough shares, withdraw what we can
                // NOTE: This logic should not be used for commitment policies that need
                // economic security or guaranteed balance reimbursement - it's only appropriate
                // for non-critical processes like optional gas reimbursement.
                uint256 sharesAvailable = _sharesBondedToThis(gasAbstractionTracker.owner);
                if (sharesAvailable > 0) {
                    IShMonad(SHMONAD).agentWithdrawFromBonded(
                        POLICY_ID, gasAbstractionTracker.owner, gasAbstractionTracker.key, sharesAvailable, 0, false
                    );
                }
            }
        }
    }

    function _handleSessionKeyFunding(
        address owner,
        address sessionKeyAddress,
        uint256 deposit
    )
        internal
        returns (uint256 remainder)
    {
        uint256 deficit = _sessionKeyBalanceDeficit(sessionKeyAddress);

        if (deficit == 0) {
            return deposit;
        }

        if (deposit >= deficit) {
            SafeTransferLib.safeTransferETH(sessionKeyAddress, deficit);
            return deposit - deficit;
        }

        if (deposit > 0) {
            SafeTransferLib.safeTransferETH(sessionKeyAddress, deposit);
            deficit -= deposit;
            deposit = 0;
        }

        if (deficit > 0) {
            // Optimistically take from from the owner's bonded balance
            // This avoids balance check in the happy path)
            try IShMonad(SHMONAD).agentWithdrawFromBonded(POLICY_ID, owner, sessionKeyAddress, deficit, 0, true) {
                // Success (owner's bonded balance sufficiently covered the gas cost)
            } catch {
                // If the owner doesn't have enough shares, withdraw what we can
                // NOTE: This logic should not be used for commitment policies that need
                // economic security or guaranteed balance reimbursement - it's only appropriate
                // for non-critical processes like optional gas reimbursement.
                uint256 amountAvailable = _amountBondedToThis(owner);
                uint256 amountToWithdraw = amountAvailable > deficit ? deficit : amountAvailable;
                if (amountToWithdraw > 0) {
                    IShMonad(SHMONAD).agentWithdrawFromBonded(
                        POLICY_ID, owner, sessionKeyAddress, amountToWithdraw, 0, true
                    );
                }
            }
        }
        return 0;
    }

    function _getNextAffordableBlock(
        uint256 maxPayment,
        uint256 targetBlock,
        uint256 highestAcceptableBlock,
        uint256 maxTaskGas,
        uint256 maxSearchGas
    )
        internal
        view
        returns (uint256 amountEstimated, uint256)
    {
        uint256 targetGasLeft = gasleft();

        // NOTE: This is an internal function and has no concept of how much gas
        // its caller needs to finish the call. If 'targetGasLeft' is set to zero and no profitable block is found prior
        // to running out
        // of gas, then this function will simply cause an EVM 'out of gas' error. The purpose of
        // the check below is to prevent an integer underflow, *not* to prevent an out of gas revert.
        if (targetGasLeft < maxSearchGas) {
            targetGasLeft = 0;
        } else {
            targetGasLeft -= maxSearchGas;
        }

        uint256 i = 1;
        while (gasleft() > targetGasLeft) {
            amountEstimated = _estimateTaskCost(targetBlock, maxTaskGas) + 1;

            if (targetBlock > highestAcceptableBlock) {
                return (0, 0);
            }

            // If block is too expensive, try jumping forwards
            if (amountEstimated > maxPayment) {
                // Distance between blocks increases incrementally as i increases.
                i += (i / 4 + 1);
                targetBlock += i;
            } else {
                return (amountEstimated, targetBlock);
            }
        }
        return (0, 0);
    }
}
