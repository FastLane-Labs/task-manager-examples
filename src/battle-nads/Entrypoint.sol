//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { BattleNad, BattleNadStats, StorageTracker, Inventory } from "./Types.sol";

import {
    SessionKey,
    SessionKeyData,
    GasAbstractionTracker
} from "lib/fastlane-contracts/src/common/relay/GasRelayTypes.sol";

import { Getters } from "./Getters.sol";
import { Errors } from "./libraries/Errors.sol";
import { Events } from "./libraries/Events.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

contract BattleNadsEntrypoint is Getters {
    using Equipment for BattleNad;
    using Equipment for Inventory;
    using StatSheet for BattleNad;

    constructor(address taskManager, address shMonad) Getters(taskManager, shMonad) { }

    // ACTION FUNCTIONS
    function moveNorth(bytes32 characterID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS - 6000 + MOVEMENT_EXTRA_GAS) {
            revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);
        }

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        uint8 newY = player.stats.y + 1;
        try this.handleMovement(player, player.stats.depth, player.stats.x, newY) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function moveSouth(bytes32 characterID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS - 6000 + MOVEMENT_EXTRA_GAS) {
            revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);
        }

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        uint8 newY = player.stats.y - 1;
        try this.handleMovement(player, player.stats.depth, player.stats.x, newY) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function moveEast(bytes32 characterID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS + MOVEMENT_EXTRA_GAS) {
            revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);
        }

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Make sure it isn't a monster
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        uint8 newX = player.stats.x + 1;
        try this.handleMovement(player, player.stats.depth, newX, player.stats.y) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function moveWest(bytes32 characterID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS + MOVEMENT_EXTRA_GAS) {
            revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);
        }

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        uint8 newX = player.stats.x - 1;
        try this.handleMovement(player, player.stats.depth, newX, player.stats.y) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function moveUp(bytes32 characterID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS + MOVEMENT_EXTRA_GAS) {
            revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);
        }

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        uint8 newDepth = player.stats.depth + 1;
        try this.handleMovement(player, newDepth, player.stats.x, player.stats.y) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function moveDown(bytes32 characterID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS + MOVEMENT_EXTRA_GAS) {
            revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);
        }

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        uint8 newDepth = player.stats.depth - 1;
        try this.handleMovement(player, newDepth, player.stats.x, player.stats.y) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function attack(bytes32 characterID, uint256 targetIndex) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Make sure it isn't a monster
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        try this.handleAttack(player, targetIndex) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function useAbility(bytes32 characterID, uint256 targetIndex, uint256 abilityIndex) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Load character
        BattleNad memory player = _loadBattleNad(characterID, true);
        player.owner = _loadOwner(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        try this.handleAbility(player, targetIndex, abilityIndex) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function ascend(bytes32 characterID) external payable GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Load character
        BattleNad memory player = _loadBattleNad(characterID, false);
        player.owner = _loadOwner(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        try this.handleAscend(player) returns (BattleNad memory result) {
            _storeBattleNad(result);
            // Commit ascend, return session key deposit to owner
            SafeTransferLib.safeTransferETH(player.owner, msg.value);
        } catch {
            // Failed to commit ascend, return deposit to session key
            // TODO: still send to owner?
            SafeTransferLib.safeTransferETH(msg.sender, msg.value);
        }
    }

    function equipWeapon(bytes32 characterID, uint8 weaponID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        try this.handleChangeWeapon(player, weaponID) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function equipArmor(bytes32 characterID, uint8 armorID) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        try this.handleChangeArmor(player, armorID) returns (BattleNad memory result) {
            _storeBattleNad(result);
        } catch {
            // Emit event
        }
    }

    function createCharacter(
        string memory name,
        uint256 strength,
        uint256 vitality,
        uint256 dexterity,
        uint256 quickness,
        uint256 sturdiness,
        uint256 luck,
        address sessionKey,
        uint256 sessionKeyDeadline
    )
        external
        payable
        CreateOrUpdateSessionKey(sessionKey, msg.sender, sessionKeyDeadline, msg.value)
        returns (bytes32 characterID)
    {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        try this.handlePlayerCreation(msg.sender, name, strength, vitality, dexterity, quickness, sturdiness, luck)
        returns (bytes32 _characterID) {
            characterID = _characterID;
        } catch {
            // Emit event
        }

        return characterID;
    }

    function allocatePoints(
        bytes32 characterID,
        uint256 newStrength,
        uint256 newVitality,
        uint256 newDexterity,
        uint256 newQuickness,
        uint256 newSturdiness,
        uint256 newLuck
    )
        external
        GasAbstracted
    {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        try this.handleAllocatePoints(
            player, newStrength, newVitality, newDexterity, newQuickness, newSturdiness, newLuck
        ) {
            // pass
        } catch {
            // Emit event
        }
    }

    function zoneChat(bytes32 characterID, string calldata message) external GasAbstracted {
        if (gasleft() < MIN_EXECUTION_GAS) revert Errors.NotEnoughGas(gasleft(), MIN_EXECUTION_GAS);

        // Load character
        BattleNad memory player = _loadBattleNad(characterID);

        // Validate character ownership
        if (player.isMonster()) revert Errors.CantControlMonster(characterID);
        if (player.owner != _abstractedMsgSender()) revert Errors.InvalidCharacterOwner(characterID, player.owner);

        // Call primary function inside of a try/catch so that gas abstraction reimbursement will persist if the
        // contract call fails
        try this.handleChat(player, message) {
            // No need to save the result
        } catch {
            // Emit event
        }
    }

    receive() external payable { }
}
