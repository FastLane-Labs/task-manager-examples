//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNad,
    BattleNadStats,
    Inventory,
    StorageTracker,
    Ability,
    AbilityTracker,
    BattleArea,
    BalanceTracker
} from "./Types.sol";

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

    address private immutable dungeonMaster;

    constructor() {
        dungeonMaster = msg.sender;
    }

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
        if (bytes(name).length > _MAX_NAME_LENGTH) {
            revert Errors.NameTooLong(bytes(name).length);
        } else if (bytes(name).length < _MIN_NAME_LENGTH) {
            revert Errors.NameTooLong(bytes(name).length);
        }

        // Generate Character ID
        bytes32 nameHash = keccak256(abi.encodePacked(name));

        uint256 nonce;
        unchecked {
            nonce = ++playerNonce;
        }
        character.id = keccak256(abi.encode(_ID_SEED, address(this), owner, nameHash, nonce));

        {
            bytes32 previousID = characters[owner];
            if (!_isValidID(previousID)) {
                previousID = namesToIDs[nameHash];
            }
            if (_isValidID(previousID)) {
                BattleNad memory oldCharacter = _loadBattleNad(previousID);
                if (!oldCharacter.isDead()) {
                    revert Errors.OwnerAlreadyExists(owner);
                }
                /*
                Inventory memory inventory = inventories[previousID];
                if (inventory.balance > 0) {
                    unchecked {
                        balances.monsterSumOfBalances += inventory.balance;
                    }
                }
                */
                _deleteBattleNad(oldCharacter);
            }
        }

        // Build character
        character.owner = owner;
        character.stats =
            _createCharacterStats(character.id, strength, vitality, dexterity, quickness, sturdiness, luck);

        // Flag for storage updates
        character.inventory = character.inventory.addWeaponToInventory(character.stats.weaponID);
        character.inventory = character.inventory.addArmorToInventory(character.stats.armorID);

        // Get health / max health
        character = _addClassStatAdjustments(character);
        character.stats.health = uint16(character.maxHealth);
        character = _removeClassStatAdjustments(character);

        // Add ownership data to storage
        _storeBattleNadStats(character.stats, character.id);
        inventories[character.id] = character.inventory;
        owners[character.id] = owner;
        characters[owner] = character.id;
        namesToIDs[nameHash] = character.id;
        characterNames[character.id] = name;
        abilityTasks[character.id] = AbilityTracker({
            ability: Ability.None,
            stage: 0,
            targetIndex: 0,
            taskAddress: _EMPTY_ADDRESS,
            targetBlock: 0
        });
        killMap[character.id] = _UNKILLED;
        characterTasks[character.id] = _NULL_ID;

        emit Events.CharacterCreated(character.id);

        return character;
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

    function addCustomCharacter(BattleNad memory customCharacter) external payable returns (bytes32 characterID) {
        require(msg.sender == dungeonMaster, "Nice try, buckaroo");
        // NOTE: Balances for movement / combat will have to be manually bonded via shmonad!

        if (bytes(customCharacter.name).length > _MAX_NAME_LENGTH) {
            revert Errors.NameTooLong(bytes(customCharacter.name).length);
        } else if (bytes(customCharacter.name).length < _MIN_NAME_LENGTH) {
            revert Errors.NameTooLong(bytes(customCharacter.name).length);
        }

        // Generate Character ID
        bytes32 nameHash = keccak256(abi.encodePacked(customCharacter.name));

        uint256 nonce;
        unchecked {
            nonce = ++playerNonce;
        }
        customCharacter.id = keccak256(abi.encode(_ID_SEED, address(this), customCharacter.owner, nameHash, nonce));

        {
            bytes32 previousID = characters[customCharacter.owner];
            if (!_isValidID(previousID)) {
                previousID = namesToIDs[nameHash];
            }
            if (_isValidID(previousID)) {
                BattleNad memory oldCharacter = _loadBattleNad(previousID);
                if (oldCharacter.stats.health != 0) {
                    revert Errors.OwnerAlreadyExists(customCharacter.owner);
                }
                _deleteBattleNad(oldCharacter);
            }
        }

        // Get health / max health
        customCharacter = _addClassStatAdjustments(customCharacter);
        customCharacter.stats.health = uint16(customCharacter.maxHealth);

        customCharacter.inventory = customCharacter.inventory.addWeaponToInventory(customCharacter.stats.weaponID);
        customCharacter.inventory = customCharacter.inventory.addArmorToInventory(customCharacter.stats.armorID);

        // Get location
        BattleArea memory area;
        if (customCharacter.stats.x == 0 || customCharacter.stats.y == 0 || customCharacter.stats.depth == 0) {
            (area, customCharacter.stats.x, customCharacter.stats.y) = _unrandomSpawnCoordinates(customCharacter);
            customCharacter.stats.depth = 1;
        } else {
            area = _loadArea(customCharacter.stats.depth, customCharacter.stats.x, customCharacter.stats.y);
        }

        customCharacter.stats.index =
            _findNextIndex(area, keccak256(abi.encode(_AREA_SEED, customCharacter.id, blockhash(block.number - 1))));
        (customCharacter, area) = _enterLocation(
            customCharacter,
            area,
            customCharacter.stats.x,
            customCharacter.stats.y,
            customCharacter.stats.depth,
            customCharacter.stats.index
        );

        // Log that we entered the new area and then store it
        area = _logEnteredArea(customCharacter, area, 0);
        _storeArea(area, customCharacter.stats.depth, customCharacter.stats.x, customCharacter.stats.y);

        // Handle balances
        BalanceTracker memory balanceTracker = balances;

        if (customCharacter.isMonster()) {
            ++balanceTracker.monsterCount;
            balanceTracker.monsterSumOfLevels += uint32(customCharacter.stats.level);
            balanceTracker.monsterSumOfBalances += uint128(msg.value);
            customCharacter.inventory.balance = uint128(0);
        } else {
            ++balanceTracker.playerCount;
            balanceTracker.playerSumOfLevels += uint32(customCharacter.stats.level);
            customCharacter.inventory.balance = uint128(msg.value);
        }

        balances = balanceTracker;

        // Prep for storage
        customCharacter = _exitCombat(customCharacter);
        customCharacter = _removeClassStatAdjustments(customCharacter);

        // Add ownership data to storage
        characters[customCharacter.owner] = customCharacter.id;
        namesToIDs[nameHash] = customCharacter.id;
        characterNames[customCharacter.id] = customCharacter.name;
        inventories[customCharacter.id] = customCharacter.inventory;
        abilityTasks[customCharacter.id] = AbilityTracker({
            ability: Ability.None,
            stage: 0,
            targetIndex: 0,
            taskAddress: _EMPTY_ADDRESS,
            targetBlock: 0
        });
        killMap[customCharacter.id] = _UNKILLED;
        characterTasks[customCharacter.id] = _NULL_ID;
        owners[customCharacter.id] = customCharacter.owner;

        emit Events.CharacterCreated(customCharacter.id);

        return customCharacter.id;
    }

    function _findNextIndex(
        BattleArea memory area,
        bytes32 randomSeed
    )
        internal
        view
        virtual
        returns (uint8 newIndex);

    function _unrandomSpawnCoordinates(BattleNad memory player)
        internal
        view
        virtual
        returns (BattleArea memory area, uint8 x, uint8 y);
}
