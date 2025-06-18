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
    PayoutTracker,
    Ability
} from "./Types.sol";

import { Errors } from "./libraries/Errors.sol";
import { StatSheet } from "./libraries/StatSheet.sol";
import { Names } from "./libraries/Names.sol";
import { Equipment } from "./libraries/Equipment.sol";

abstract contract Storage {
    using StatSheet for BattleNad;
    using StatSheet for BattleNadStats;
    using Names for BattleNad;
    using Names for BattleNadLite;
    using Equipment for BattleNadLite;

    error Storage_InvalidIndex(uint256 index);
    error Storage_InvalidBlock(uint256 blockNumber);

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

    // Character (or monster) ID -> Combat Task ID
    mapping(bytes32 => bytes32) public characterTasks;

    // Character (or monster) ID -> Ability Task address
    mapping(bytes32 => AbilityTracker) public abilityTasks;

    // Deceased Character ID -> Killer Character ID or standin
    mapping(bytes32 => bytes32) public killMap;

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
    bytes32 internal constant _UNKILLED = bytes32(uint256(2));
    bytes32 internal constant _KILL_PROCESSED = bytes32(uint256(3));
    bytes32 internal constant _SYSTEM_KILLER = bytes32(uint256(4));

    function _loadArea(uint8 depth, uint8 x, uint8 y) internal view returns (BattleArea memory area) {
        area = areaData[depth][x][y];
    }

    function _loadArea(BattleNad memory character) internal view returns (BattleArea memory) {
        return _loadArea(character.stats.depth, character.stats.x, character.stats.y);
    }

    function _storeArea(BattleArea memory area, uint8 depth, uint8 x, uint8 y) internal {
        if (area.update) {
            area.update = false;
            if (area.playerBitMap == 0 && area.monsterBitMap == 0) {
                area = _clearArea(area);
            } else if (area.playerBitMap == 0) {
                area.playerCount = 0;
                area.sumOfPlayerLevels = 0;
            } else if (area.monsterBitMap == 0) {
                area.monsterCount = 0;
                area.sumOfMonsterLevels = 0;
            }
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
        if (character.isDead()) {
            character.tracker.died = true;
        }
        return character;
    }

    function _loadBattleNad(bytes32 characterID) internal view returns (BattleNad memory) {
        BattleNad memory character = _loadBattleNad(characterID, false);
        // character.activeTask = characterTasks[characterID];
        character.owner = owners[characterID];
        if (character.isDead()) {
            character.tracker.died = true;
        }
        return character;
    }

    function _loadOwner(bytes32 characterID) internal view returns (address owner) {
        owner = owners[characterID];
    }

    function _loadAbility(bytes32 characterID) internal view returns (AbilityTracker memory activeAbility) {
        activeAbility = abilityTasks[characterID];
    }

    function _loadActiveTaskAddress(bytes32 characterID) internal view returns (address taskAddress) {
        taskAddress = address(uint160(uint256(characterTasks[characterID])));
    }

    function _loadActiveTaskID(bytes32 characterID) internal view returns (bytes32 taskID) {
        taskID = characterTasks[characterID];
    }

    function _clearActiveTask(bytes32 characterID) internal {
        characterTasks[characterID] = _NULL_ID;
    }

    function _storeActiveTask(bytes32 characterID, bytes32 taskID) internal {
        characterTasks[characterID] = taskID;
    }

    function _hackyUpdateTaskID(bytes32 characterID, uint256 scheduledBlock) internal {
    /*
        environment = address(uint160(uint256(packedTask)));
        initBlock = uint64(uint256(packedTask) >> 160);
        initIndex = uint16(uint256(packedTask) >> 224);
        size = Size(uint8(uint256(packedTask) >> 240));
        cancelled = uint8(uint256(packedTask) >> 248) == 1;

        packedTask = bytes32(
            uint256(uint160(environment)) | (uint256(initBlock) << 160) | (uint256(initIndex) << 224)
                | (uint256(size) << 240) | (uint256(cancelled ? 1 : 0) << 248)
        );
    */

        if (++scheduledBlock > type(uint64).max) revert Storage_InvalidBlock(scheduledBlock);

        bytes32 oldTaskID = _loadActiveTaskID(characterID);

        // Clear old the old block and index
        oldTaskID &= 0xffff00000000000000000000ffffffffffffffffffffffffffffffffffffffff;

        oldTaskID |= bytes32(scheduledBlock<<160);

        // Assume in-block-index is 1 (false positives are tolerable, false negatives are breaking)
        oldTaskID |= 0x0000000100000000000000000000000000000000000000000000000000000000;

        characterTasks[characterID] = oldTaskID;
    }

    function _clearAbility(bytes32 characterID) internal {
        abilityTasks[characterID] = AbilityTracker({
            ability: Ability.None,
            stage: uint8(0),
            targetIndex: uint8(0),
            taskAddress: _EMPTY_ADDRESS,
            targetBlock: uint64(0)
        });
    }

    function _clearArea(BattleArea memory area) internal pure returns (BattleArea memory) {
        area.playerCount = uint8(0);
        area.sumOfPlayerLevels = uint16(0);
        area.monsterCount = uint8(0);
        area.sumOfMonsterLevels = uint16(0);
        area.playerBitMap = uint64(0);
        area.monsterBitMap = uint64(0);
        if (area.lastLogBlock == uint64(0)) area.lastLogBlock = uint64(1);
        area.update = true;
        return area;
    }

    function _getKiller(bytes32 deceasedID) internal view returns (bytes32 killerID, bool valid) {
        bytes32 killerID = killMap[deceasedID];
        if (killerID == _UNKILLED || killerID == _KILL_PROCESSED || !_isValidID(killerID)) {
            killerID = _NULL_ID;
            return (killerID, false);
        }
        return (killerID, true);
    }

    function _setKiller(bytes32 deceasedID, bytes32 killerID) internal returns (bool valid) {
        bytes32 currentStatus = killMap[deceasedID];
        if (currentStatus == _UNKILLED && _isValidID(killerID)) {
            killMap[deceasedID] = killerID;
            valid = true;
        }
    }

    function _finalizeKiller(bytes32 deceasedID, bytes32 killerID) internal returns (bool valid) {
        bytes32 currentStatus = killMap[deceasedID];
        if (
            currentStatus == killerID && currentStatus != _UNKILLED && currentStatus != _KILL_PROCESSED
                && _isValidID(killerID)
        ) {
            killMap[deceasedID] = _KILL_PROCESSED;
            valid = true;
        }
    }

    function _storeBattleNad(BattleNad memory character) internal {
        if (!_isValidID(character.id)) return;
        if (character.tracker.died) {
            character.stats.health = 0;
        }
        if (character.stats.combatantBitMap == uint64(0)) {
            character = _exitCombat(character);
        }
        if (character.tracker.updateStats) {
            character = _removeClassStatAdjustments(character);
            _storeBattleNadStats(character.stats, character.id);
        }
        if (character.tracker.updateInventory) {
            inventories[character.id] = character.inventory;
        }
        if (character.tracker.updateOwner) {
            owners[character.id] = character.owner;
        }
        if (character.tracker.updateActiveAbility) {
            abilityTasks[character.id] = character.activeAbility;
        }
    }

    function _loadBattleNadStats(bytes32 characterID) internal view returns (BattleNadStats memory stats) {
        stats = characterStats[characterID];
    }

    function _storeBattleNadStats(BattleNadStats memory stats, bytes32 characterID) internal {
        if (stats.isDead()) {
            stats.health = 0;
        }
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

    function _isDeadUnaware(bytes32 deceasedID) internal view returns (bool) {
        return killMap[deceasedID] == _UNKILLED;
    }

    function _isDeadUnprocessed(bytes32 deceasedID) internal view returns (bool) {
        bytes32 currentStatus = killMap[deceasedID];
        return currentStatus != _UNKILLED && currentStatus != _KILL_PROCESSED && _isValidID(currentStatus);
    }

    function _exitCombat(BattleNad memory combatant) internal pure virtual returns (BattleNad memory);

    function _removeClassStatAdjustments(BattleNad memory combatant) internal pure virtual returns (BattleNad memory);

    function _addClassStatAdjustments(BattleNad memory combatant) internal pure virtual returns (BattleNad memory);
}
