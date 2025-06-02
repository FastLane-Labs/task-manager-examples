//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { ITaskManager } from "@fastlane-contracts/task-manager/interfaces/ITaskManager.sol";
import { ITaskHandler } from "../interfaces/ITaskHandler.sol";
import { IShMonad } from "@fastlane-contracts/shmonad/interfaces/IShMonad.sol";
import { Errors } from "../libraries/Errors.sol";

import { BattleNad, BattleNadStats, Inventory, Weapon, Armor, StorageTracker } from "../Types.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BattleNadsImplementation {
    error MustBeDelegated();
    error CantAffordReschedule(uint256 balance, uint256 cost);

    address private immutable _BATTLE_NADS;
    address private immutable _IMPLEMENTATION;

    address private constant _SHMONAD = address(0x3a98250F98Dd388C211206983453837C8365BDc1);
    uint256 private constant _MIN_RESCHEDULE_GAS = 45_500;

    constructor() {
        _BATTLE_NADS = msg.sender;
        _IMPLEMENTATION = address(this);
    }

    function execute(bytes32 characterID) external {
        if (address(this) == _IMPLEMENTATION) {
            revert MustBeDelegated();
        }
        // Leave enough room for rescheduling
        // NOTE: Some functions inside processTurn will iterate until gasleft() is low
        uint256 gasLimit = gasleft() > _MIN_RESCHEDULE_GAS ? gasleft() - _MIN_RESCHEDULE_GAS : gasleft();

        // Process the turn
        (bool reschedule, uint256 nextBlock, uint256 maxPayment) =
            ITaskHandler(_BATTLE_NADS).processTurn{ gas: gasLimit }(characterID);

        // Check for value - could be sent from battlenads or just leftover
        uint256 value = address(this).balance;
        if (!reschedule) {
            if (value > 0 && gasleft() > 25_000) {
                IShMonad(_SHMONAD).boostYield{ value: value }();
            }
            return;
        }

        if (value < maxPayment) {
            revert CantAffordReschedule(value, maxPayment);
        }

        // Reschedule the task
        (bool rescheduled, uint256 executionCost, bytes32 taskId) =
            ITaskManager(msg.sender).rescheduleTask{ value: maxPayment }(uint64(nextBlock), maxPayment);

        if (!rescheduled) {
            revert Errors.TaskNotRescheduled();
        }
    }

    function ability(bytes32 characterID) external {
        if (address(this) == _IMPLEMENTATION) {
            revert MustBeDelegated();
        }
        // Leave enough room for rescheduling
        // NOTE: Some functions inside processTurn will iterate until gasleft() is low
        uint256 gasLimit = gasleft() > _MIN_RESCHEDULE_GAS ? gasleft() - _MIN_RESCHEDULE_GAS : gasleft();

        // Process the turn
        (bool reschedule, uint256 nextBlock, uint256 maxPayment) =
            ITaskHandler(_BATTLE_NADS).processAbility{ gas: gasLimit }(characterID);

        // Check for value - could be sent from battlenads or just leftover
        uint256 value = address(this).balance;
        if (!reschedule) {
            if (value > 0 && gasleft() > 25_000) {
                IShMonad(_SHMONAD).boostYield{ value: value }();
            }
            return;
        }

        if (value < maxPayment) {
            revert CantAffordReschedule(value, maxPayment);
        }

        // Reschedule the task
        (bool rescheduled, uint256 executionCost, bytes32 taskId) =
            ITaskManager(msg.sender).rescheduleTask{ value: maxPayment }(uint64(nextBlock), maxPayment);

        if (!rescheduled) {
            revert Errors.TaskNotRescheduled();
        }
    }

    function ascend(bytes32 characterID) external {
        if (address(this) == _IMPLEMENTATION) {
            revert MustBeDelegated();
        }
        // Process the ascend
        ITaskHandler(_BATTLE_NADS).processAscend(characterID);

        // No reschedule
    }

    function spawn(bytes32 characterID) external {
        if (address(this) == _IMPLEMENTATION) {
            revert MustBeDelegated();
        }
        // Leave enough room for rescheduling
        // NOTE: Some functions inside processTurn will iterate until gasleft() is low
        uint256 gasLimit = gasleft() > _MIN_RESCHEDULE_GAS ? gasleft() - _MIN_RESCHEDULE_GAS : gasleft();

        // Process the turn
        (bool reschedule, uint256 nextBlock, uint256 maxPayment) =
            ITaskHandler(_BATTLE_NADS).processSpawn{ gas: gasLimit }(characterID);

        // Check for value - could be sent from battlenads or just leftover
        uint256 value = address(this).balance;
        if (!reschedule) {
            if (value > 0 && gasleft() > 25_000) {
                IShMonad(_SHMONAD).boostYield{ value: value }();
            }
            return;
        }

        if (value < maxPayment) {
            revert CantAffordReschedule(value, maxPayment);
        }

        // Reschedule the task
        (bool rescheduled, uint256 executionCost, bytes32 taskId) =
            ITaskManager(msg.sender).rescheduleTask{ value: maxPayment }(uint64(nextBlock), maxPayment);

        if (!rescheduled) {
            revert Errors.TaskNotRescheduled();
        }
    }

    receive() external payable { }
}
