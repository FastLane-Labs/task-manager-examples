//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { ITaskManager } from "@fastlane-task-manager/src/interfaces/ITaskManager.sol";
import { ITaskHandler } from "../interfaces/ITaskHandler.sol";
import { Errors } from "../libraries/Errors.sol";
import { BattleNad, BattleNadStats, Inventory, Weapon, Armor, StorageTracker } from "../Types.sol";

contract BattleNadsImplementation {
    error MustBeDelegated();

    address private immutable _BATTLE_NADS;
    address private immutable _IMPLEMENTATION;

    uint256 private constant _MIN_RESCHEDULE_GAS = 25_500;

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
        (bool reschedule, uint256 nextBlock, uint256 maxPayment) = ITaskHandler(_BATTLE_NADS).processTurn{gas: gasLimit}(characterID);
        if (!reschedule) {
            return;
        }

        // Reschedule the task
        (bool rescheduled, uint256 executionCost, bytes32 taskId) =
            ITaskManager(msg.sender).rescheduleTask(uint64(nextBlock), maxPayment);

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
            ITaskHandler(_BATTLE_NADS).processAbility{gas: gasLimit}(characterID);
        if (!reschedule) {
            return;
        }

        // Reschedule the task
        (bool rescheduled, uint256 executionCost, bytes32 taskId) =
            ITaskManager(msg.sender).rescheduleTask(uint64(nextBlock), maxPayment);

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
        (bool reschedule, uint256 nextBlock, uint256 maxPayment) = ITaskHandler(_BATTLE_NADS).processSpawn{gas: gasLimit}(characterID);
        if (!reschedule) {
            return;
        }

        // Reschedule the task
        (bool rescheduled, uint256 executionCost, bytes32 taskId) =
            ITaskManager(msg.sender).rescheduleTask(uint64(nextBlock), maxPayment);

        if (!rescheduled) {
            revert Errors.TaskNotRescheduled();
        }
    }
}
