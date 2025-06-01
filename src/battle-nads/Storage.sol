//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    CharacterClass,
    BattleNadStats,
    BattleNad,
    BattleNadLite,
    Inventory,
    BalanceTracker,
    BattleArea,
    AbilityTracker,
    LogType,
    Log,
    PayoutTracker
} from "./Types.sol";

import { Errors } from "./libraries/Errors.sol";
import { StatSheet } from "./libraries/StatSheet.sol";
import { Names } from "./libraries/Names.sol";
import { Equipment } from "./libraries/Equipment.sol";

abstract contract Storage {
    using StatSheet for BattleNad;
    using Names for BattleNad;
    using Names for BattleNadLite;
    using Equipment for BattleNadLite;

    // Character ID -> Owner
    mapping(bytes32 => address) public owners;

    // Owner -> Character ID
    mapping(address => bytes32) public characters;

    // Character ID -> Character Name
    mapping(bytes32 => string) public characterNames;

    // Character ID -> Character Stats
    // mapping(bytes32 => uint256) public characterStats;
    mapping(bytes32 => BattleNadStats) public characterStats;

    // Character ID -> Character Inventory Bitmap
    mapping(bytes32 => Inventory) public inventories;

    // keccak(Character Name) -> Character ID
    mapping(bytes32 => bytes32) public namesToIDs;

    // Character (or monster) ID -> Combat Task Address
    mapping(bytes32 => address) public characterTasks;

    // Character (or monster) ID -> Ability Task address
    mapping(bytes32 => AbilityTracker) public abilityTasks;

    // Depth ID -> X -> Y -> BattleArea
    mapping(uint8 => mapping(uint8 => mapping(uint8 => BattleArea))) public areaData;

    // Depth ID -> X -> Y -> Area's Combatants
    mapping(uint8 => mapping(uint8 => mapping(uint8 => bytes32[64]))) public areaCombatants;

    // Log Space ID -> Log Index -> Log
    mapping(bytes32 => mapping(uint256 => Log)) public logs;

    // Chat Log ID -> Chat string
    mapping(bytes32 => string) public chatLogs;

    // For tracking inventory / balance drops
    BalanceTracker public balances = BalanceTracker({
        playerCount: 0,
        playerSumOfLevels: 0,
        monsterCount: 1, // make it non-null
        monsterSumOfLevels: 1,
        monsterSumOfBalances: 0
    });

    // For tracking players
    uint256 public playerNonce;

    // For tracking monsters
    uint256 public monsterNonce;

    // PLACEHOLDER NULL VALUES FOR GAS OPTIMIZATION
    address internal constant _EMPTY_ADDRESS = address(uint160(uint256(1)));
    bytes32 internal constant _NULL_ID = bytes32(uint256(1));

    function _loadArea(uint8 depth, uint8 x, uint8 y) internal view returns (BattleArea memory area) {
        area = areaData[depth][x][y];
    }

    function _loadArea(BattleNad memory character) internal view returns (BattleArea memory) {
        return _loadArea(character.stats.depth, character.stats.x, character.stats.y);
    }

    function _storeArea(BattleArea memory area, uint8 depth, uint8 x, uint8 y) internal {
        if (area.update) {
            area.update = false;
            areaData[depth][x][y] = area;
        }
    }

    function _storeArea(BattleArea memory area, BattleNad memory character) internal {
        _storeArea(area, character.stats.depth, character.stats.x, character.stats.y);
    }

    function _loadBattleNad(bytes32 characterID, bool adjustStats) internal view returns (BattleNad memory character) {
        character.id = characterID;
        character.stats = _loadBattleNadStats(characterID);
        if (adjustStats) {
            character = _addClassStatAdjustments(character);
        }
        return character;
    }

    function _loadBattleNad(bytes32 characterID) internal view returns (BattleNad memory) {
        BattleNad memory character = _loadBattleNad(characterID, false);
        character.activeTask = characterTasks[characterID];
        character.owner = owners[characterID];
        return character;
    }

    function _loadOwner(bytes32 characterID) internal view returns (address owner) {
        owner = owners[characterID];
    }

    function _loadAbility(bytes32 characterID) internal view returns (AbilityTracker memory activeAbility) {
        activeAbility = abilityTasks[characterID];
    }

    function _loadActiveTask(bytes32 characterID) internal view returns (address task) {
        task = characterTasks[characterID];
    }

    function _storeBattleNad(BattleNad memory character) internal {
        if (!_isValidID(character.id)) return;
        if (character.tracker.updateStats) {
            character = _removeClassStatAdjustments(character);
            _storeBattleNadStats(character.stats, character.id);
        }
        if (character.tracker.updateInventory) {
            inventories[character.id] = character.inventory;
        }
        if (character.tracker.updateActiveTask) {
            characterTasks[character.id] = character.activeTask;
        }
        if (character.tracker.updateOwner) {
            owners[character.id] = character.owner;
        }
        if (character.tracker.updateActiveAbility) {
            abilityTasks[character.id] = character.activeAbility;
        }
    }

    function _loadBattleNadStats(bytes32 characterID) internal view returns (BattleNadStats memory stats) {
        /*
        uint256 packedStats = characterStats[characterID];
        {
            // Combat Properties
            stats.combatantBitMap = uint64(packedStats); // uint64
            stats.nextTargetIndex = uint8(packedStats >> 64); //uint8
            stats.combatants = uint8(packedStats >> 72); // uint8
            stats.sumOfCombatantLevels = uint8(packedStats >> 80); // uint8
            stats.health = uint16(packedStats >> 88); // uint16
        }
        {
            // Location and Equipment
            stats.armorID = uint8(packedStats >> 104); // uint8
            stats.weaponID = uint8(packedStats >> 112); // uint8
            stats.index = uint8(packedStats >> 120); // uint8
            stats.y = uint8(packedStats >> 128); // uint8
            stats.x = uint8(packedStats >> 136); // uint8
            stats.depth = uint8(packedStats >> 144); // uint8
        }
        {
            // Attributes
            stats.luck = uint8(packedStats >> 152); // uint8
            stats.sturdiness = uint8(packedStats >> 160); // uint8
            stats.quickness = uint8(packedStats >> 168); // uint8
            stats.dexterity = uint8(packedStats >> 176); // uint8
            stats.vitality = uint8(packedStats >> 184); // uint8
            stats.strength = uint8(packedStats >> 192); // uint8
        }
        {
            // Progress
            stats.experience = uint16(packedStats >> 200); // uint16
            stats.unspentAttributePoints = uint8(packedStats >> 216); // uint8
            stats.level = uint8(packedStats >> 224); // uint8
            stats.debuffs = uint8(packedStats >> 232); // uint8
            stats.buffs = uint8(packedStats >> 240); // uint8
            stats.class = CharacterClass(uint8(packedStats >> 248)); // uint8
        }
        return stats;
        */
        stats = characterStats[characterID];
    }

    function _storeBattleNadStats(BattleNadStats memory stats, bytes32 characterID) internal {
        /*
        uint256 packedStats;
        {
            // Combat Properties
            packedStats |= (
                uint256(stats.combatantBitMap) // uint64
                    | uint256(stats.nextTargetIndex) << 64 //uint8
                    | uint256(stats.combatants) << 72 // uint8
                    | uint256(stats.sumOfCombatantLevels) << 80 // uint8
                    | uint256(stats.health) << 88
            ); // uint16
        }
        {
            // Location and Equipment
            packedStats |= (
                uint256(stats.armorID) << 104 // uint8
                    | uint256(stats.weaponID) << 112 // uint8
                    | uint256(stats.index) << 120 // uint8
                    | uint256(stats.y) << 128 // uint8
                    | uint256(stats.x) << 136 // uint8
                    | uint256(stats.depth) << 144
            ); // uint8
        }
        {
            // Attributes
            packedStats |= (
                uint256(stats.luck) << 152 // uint8
                    | uint256(stats.sturdiness) << 160 // uint8
                    | uint256(stats.quickness) << 168 // uint8
                    | uint256(stats.dexterity) << 176 // uint8
                    | uint256(stats.vitality) << 184 // uint8
                    | uint256(stats.strength) << 192
            ); // uint8
        }
        {
            // Progress
            packedStats |= (
                uint256(stats.experience) << 200 // uint16
                    | uint256(stats.unspentAttributePoints) << 216 // uint8
                    | uint256(stats.level) << 224 // uint8
                    | uint256(stats.debuffs) << 232 // uint8
                    | uint256(stats.buffs) << 240 // uint8
                    | uint256(uint8(stats.class)) << 248
            ); // uint8
        }
        characterStats[characterID] = packedStats;
        */
        characterStats[characterID] = stats;
    }

    function _deleteBattleNad(BattleNad memory combatant) internal {
        // Don't delete owner's link to character if this is a monster
        if (!combatant.isMonster()) {
            combatant = _removeClassStatAdjustments(combatant);

            if (_isValidAddress(combatant.owner)) {
                characters[combatant.owner] = _NULL_ID;
            }

            string memory name = characterNames[combatant.id];
            bytes32 nameHash = keccak256(abi.encodePacked(name));
            namesToIDs[nameHash] = _NULL_ID;

            BattleNadStats memory cleanedStats;
            cleanedStats.class = combatant.stats.class;
            cleanedStats.level = combatant.stats.level;
            cleanedStats.strength = combatant.stats.strength;
            cleanedStats.vitality = combatant.stats.vitality;
            cleanedStats.dexterity = combatant.stats.dexterity;
            cleanedStats.quickness = combatant.stats.quickness;
            cleanedStats.sturdiness = combatant.stats.sturdiness;
            cleanedStats.luck = combatant.stats.luck;

            _storeBattleNadStats(cleanedStats, combatant.id);

            delete inventories[combatant.id];
        }

        delete owners[combatant.id];
        // delete characterTasks[combatant.id];
        // delete characterNames[combatant.id];
        // delete characterStats[combatant.id];

        //characterStats[combatant.id] = cleanedStats;
    }

    function _isValidAddress(address target) internal pure returns (bool) {
        // return target != address(0) && target != _EMPTY_ADDRESS;
        return uint256(uint160(target)) > 1;
    }

    function _isValidID(bytes32 target) internal pure returns (bool) {
        // return target != bytes32(0) && target != _NULL_ID;
        return uint256(target) > 1;
    }

    function _removeClassStatAdjustments(BattleNad memory combatant) internal pure virtual returns (BattleNad memory);

    function _addClassStatAdjustments(BattleNad memory combatant) internal pure virtual returns (BattleNad memory);
}
