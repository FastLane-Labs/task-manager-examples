//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { BattleNad, BattleNadStats, BattleArea, Inventory, StorageTracker, CharacterClass } from "./Types.sol";

import { Constants } from "./Constants.sol";
import { Errors } from "./libraries/Errors.sol";
import { Character } from "./Character.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { StatSheet } from "./libraries/StatSheet.sol";
import { Events } from "./libraries/Events.sol";

abstract contract CharacterFactory is Character {
    using Equipment for BattleNad;
    using StatSheet for BattleNad;
    using Equipment for Inventory;

    function _buildNewCharacter(
        address owner,
        string memory name,
        uint256 strength,
        uint256 vitality,
        uint256 dexterity,
        uint256 quickness,
        uint256 sturdiness,
        uint256 luck
    )
        internal
        returns (BattleNad memory character)
    {
        // Make sure character is available and not already playing
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        if (characterIDs[nameHash] != bytes32(0)) {
            revert Errors.NameAlreadyExists(nameHash);
        }

        if (bytes(name).length > _MAX_NAME_LENGTH) {
            revert Errors.NameTooLong(bytes(name).length);
        } else if (bytes(name).length < _MIN_NAME_LENGTH) {
            revert Errors.NameTooLong(bytes(name).length);
        }

        // Generate Character ID
        uint256 nonce;
        unchecked {
            nonce = ++playerNonce;
        }
        character.id = keccak256(abi.encode(_ID_SEED, address(this), owner, nameHash, nonce));

        {
            bytes32 previousID = characters[owner];
            if (previousID != bytes32(0)) {
                BattleNad memory oldCharacter = _loadBattleNad(previousID);
                if (oldCharacter.stats.health != 0) {
                    revert Errors.OwnerAlreadyExists(owner);
                }
                Inventory memory inventory = inventories[previousID];
                balances.monsterSumOfBalances += inventory.balance;
                _deleteBattleNad(oldCharacter);
            }
        }

        // Build character
        character.owner = owner;
        character.stats =
            _createCharacterStats(character.id, strength, vitality, dexterity, quickness, sturdiness, luck);

        // Get health / max health
        character = _addClassStatAdjustments(character);
        character.stats.health = uint16(character.maxHealth);

        // Flag for storage updates
        character.tracker.updateInventory = true;
        character.tracker.updateStats = true;

        // Add ownership data to storage
        characters[owner] = character.id;
        owners[character.id] = owner;
        characterIDs[nameHash] = character.id;
        characterNames[character.id] = name; // TODO: Add a length limit on name

        emit Events.CharacterCreated(character.id);

        return _removeClassStatAdjustments(character);
    }

    function _createCharacterStats(
        bytes32 characterID,
        uint256 strength,
        uint256 vitality,
        uint256 dexterity,
        uint256 quickness,
        uint256 sturdiness,
        uint256 luck
    )
        internal
        view
        returns (BattleNadStats memory characterSheet)
    {
        // Make sure the stats are valid
        if (strength + vitality + dexterity + quickness + sturdiness + luck != STARTING_STAT_SUM) {
            revert Errors.CreationStatsMustSumToTarget(
                strength + vitality + dexterity + quickness + sturdiness + luck, STARTING_STAT_SUM
            );
        }

        if (
            strength < MIN_STAT_VALUE || vitality < MIN_STAT_VALUE || dexterity < MIN_STAT_VALUE
                || quickness < MIN_STAT_VALUE || sturdiness < MIN_STAT_VALUE || luck < MIN_STAT_VALUE
        ) {
            revert Errors.CreationStatsMustAllBeAboveMin(MIN_STAT_VALUE);
        }

        // Build character sheet
        characterSheet.strength = uint8(strength);
        characterSheet.vitality = uint8(vitality);
        characterSheet.dexterity = uint8(dexterity);
        characterSheet.quickness = uint8(quickness);
        characterSheet.sturdiness = uint8(sturdiness);
        characterSheet.luck = uint8(luck);

        // Fill out with default combat values
        characterSheet.combatants = uint8(0);
        characterSheet.nextTargetIndex = uint8(0);
        characterSheet.combatantBitMap = uint64(0);

        // Start level / XP at 0
        characterSheet.level = uint8(1);
        characterSheet.experience = uint16(0);

        // Assign class
        characterSheet.class = _getPlayerClass(characterID);

        // Get starting weapon and armor
        // NOTE: Starting weapon and armor will be from IDs 1,2, 3, or 4
        uint8 randomSeed =
            uint8(uint256(keccak256(abi.encode(_CHARACTER_SEED, characterID, blockhash(block.number - 1)))));
        if (randomSeed == 0 || uint256(randomSeed) + luck > 127) {
            characterSheet.weaponID = uint8(4);
            characterSheet.armorID = uint8(4);
        } else if (randomSeed > 96) {
            characterSheet.weaponID = uint8(4);
            characterSheet.armorID = uint8(1);
        } else if (randomSeed > 64) {
            characterSheet.weaponID = uint8(3);
            characterSheet.armorID = uint8(2);
        } else if (randomSeed > 32) {
            characterSheet.weaponID = uint8(2);
            characterSheet.armorID = uint8(3);
        } else if (randomSeed > 8) {
            characterSheet.weaponID = uint8(1);
            characterSheet.armorID = uint8(4);
        } else if (randomSeed > 4) {
            characterSheet.weaponID = uint8(3);
            characterSheet.armorID = uint8(3);
        } else {
            characterSheet.weaponID = uint8(1);
            characterSheet.armorID = uint8(1);
        }
    }
}
