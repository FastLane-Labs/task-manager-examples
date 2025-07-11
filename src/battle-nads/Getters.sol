//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNad,
    BattleNadStats,
    BattleNadLite,
    AbilityTracker,
    BattleArea,
    Inventory,
    Weapon,
    Armor,
    DataFeed
} from "./Types.sol";

import { SessionKeyData } from "lib/fastlane-contracts/src/common/relay/types/GasRelayTypes.sol";

import { TaskHandler } from "./TaskHandler.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { StatSheet } from "./libraries/StatSheet.sol";
import { Names } from "./libraries/Names.sol";

contract Getters is TaskHandler {
    using Equipment for BattleNad;
    using Equipment for BattleNadLite;
    using Equipment for Inventory;
    using StatSheet for BattleNad;
    using StatSheet for BattleNadLite;
    using StatSheet for BattleNadStats;
    using Names for BattleNad;
    using Names for BattleNadLite;

    constructor(address taskManager, address shMonad) TaskHandler(taskManager, shMonad) { }

    // Getters

    // FOR THE LOVE OF ALL THAT IS GOOD, DO NOT CALL THIS ON CHAIN!
    function pollForFrontendData(
        address owner,
        uint256 startBlock
    )
        public
        view
        returns (
            bytes32 characterID,
            SessionKeyData memory sessionKeyData,
            BattleNad memory character,
            BattleNadLite[] memory combatants,
            BattleNadLite[] memory noncombatants,
            uint8[] memory equipableWeaponIDs,
            string[] memory equipableWeaponNames,
            uint8[] memory equipableArmorIDs,
            string[] memory equipableArmorNames,
            DataFeed[] memory dataFeeds,
            uint256 balanceShortfall,
            uint256 endBlock
        )
    {
        characterID = characters[owner];
        sessionKeyData = getCurrentSessionKeyData(owner);
        character = getBattleNad(characterID);
        balanceShortfall =
            _shortfallToRecommendedBalanceInMON(character) * BALANCE_SHORTFALL_FACTOR / BALANCE_SHORTFALL_BASE;
        combatants = _getCombatantBattleNads(characterID);
        noncombatants = _getNonCombatantBattleNads(characterID);
        (equipableWeaponIDs, equipableWeaponNames,) = _getEquippableWeapons(characterID);
        (equipableArmorIDs, equipableArmorNames,) = _getEquippableArmor(characterID);
        if (startBlock >= block.number) {
            startBlock = block.number - 1;
        } else if (startBlock < block.number - 20) {
            startBlock = block.number - 20;
        }
        endBlock = block.number;
        dataFeeds = _getDataFeedForRange(character, startBlock, endBlock);
    }

    function getDataFeed(
        address owner,
        uint256 startBlock,
        uint256 endBlock
    )
        public
        view
        returns (DataFeed[] memory dataFeeds)
    {
        bytes32 characterID = characters[owner];
        BattleNad memory character = getBattleNad(characterID);

        if (startBlock == 0) {
            startBlock = block.number - 1;
        } else if (startBlock > block.number) {
            startBlock = block.number;
        }
        if (endBlock < startBlock || endBlock > block.number) {
            endBlock = block.number;
        }
        dataFeeds = _getDataFeedForRange(character, startBlock, endBlock);
        return dataFeeds;
    }

    /**
     * @notice Get all character IDs owned by a specific address
     * @param owner Address to query characters for
     * @return characterID Array of character IDs owned by the address
     */
    function getPlayerCharacterID(address owner) external view returns (bytes32 characterID) {
        // Get all character IDs associated with this owner
        characterID = characters[owner];
    }

    // FOR THE LOVE OF ALL THAT IS GOOD, DO NOT CALL THIS ON CHAIN!
    function getBattleNad(bytes32 characterID) public view returns (BattleNad memory character) {
        character = _loadBattleNad(characterID, true);
        character.activeTask = _buildCombatTracker(character);
        character.inventory = inventories[characterID];

        if (!character.isDead()) {
            character = character.loadEquipment();
            if (!character.isMonster()) {
                character.activeAbility = _loadAbility(characterID);
            }
        } else {
            character.stats.health = 0;
        }

        if (!character.isMonster()) {
            character.name = characterNames[characterID];
        }
        return character.addName();
    }

    // FOR THE LOVE OF ALL THAT IS GOOD, DO NOT CALL THIS ON CHAIN!
    function getBattleNadLite(bytes32 characterID) public view returns (BattleNadLite memory character) {
        BattleNad memory fullCharacter = _loadBattleNad(characterID, true);
        character.id = characterID;
        character.class = fullCharacter.stats.class;
        if (fullCharacter.isDead()) {
            character.isDead = true;
            character.health = 0;
        } else {
            character.health = uint256(fullCharacter.stats.health);
        }
        character.maxHealth = fullCharacter.maxHealth;
        character.buffs = uint256(fullCharacter.stats.buffs);
        character.debuffs = uint256(fullCharacter.stats.debuffs);
        character.level = uint256(fullCharacter.stats.level);
        character.index = uint256(fullCharacter.stats.index);
        character.combatantBitMap = uint256(fullCharacter.stats.combatantBitMap);

        if (!character.isDead) {
            character = character.loadEquipment(fullCharacter.stats);
        } else {
            character.health = 0;
        }

        if (!character.isMonster()) {
            if (!character.isDead) {
                AbilityTracker memory activeAbility = abilityTasks[characterID];

                character.ability = activeAbility.ability;
                character.abilityStage = uint256(activeAbility.stage);

                // Offset target block because frontend will read this ~3 blocks behind
                character.abilityTargetBlock = uint256(activeAbility.targetBlock) + 4;
            }

            character.name = characterNames[characterID];
        }
        return character.addName();
    }

    /*
    function getMiniMap(bytes32 characterID) public view returns (BattleArea[5][5] memory miniMap) {
        BattleNad memory character = _loadBattleNad(characterID);
        uint8 depth = character.stats.depth;
        uint8 x = character.stats.x;
        uint8 y = character.stats.y;

        for (uint8 i; i < 5; i++) {
            if (i < 2 && x < 2 - i) {
                continue;
            } else if (i > 2 && x > MAX_DUNGEON_X + (i - 2)) {
                continue;
            }

            uint8 _x = x + i - 2;

            for (uint8 j; j < 5; j++) {
                if (j < 2 && y < 2 - j) {
                    continue;
                } else if (j > 2 && y > MAX_DUNGEON_Y + (j - 2)) {
                    continue;
                }

                uint8 _y = y + j - 2;

                BattleArea memory area = _loadArea(depth, _x, _y);

                miniMap[i][j] = area;
            }
        }
    }
    */

    function shortfallToRecommendedBalanceInMON(bytes32 characterID) external view returns (uint256 minAmount) {
        // Load character
        BattleNad memory player = _loadBattleNad(characterID);
        uint256 shortfall = _shortfallToRecommendedBalanceInMON(player);
        if (shortfall == 0) {
            return 0;
        }
        uint256 recommendedBalance = _getRecommendedBalanceInMON();
        return
            ((recommendedBalance + shortfall) * BALANCE_SHORTFALL_FACTOR / BALANCE_SHORTFALL_BASE) - recommendedBalance;
    }

    function estimateBuyInAmountInMON() external view returns (uint256 minAmount) {
        minAmount =
            (_getBuyInAmountInMON() + _targetSessionKeyBalance()) * BALANCE_SHORTFALL_FACTOR / BALANCE_SHORTFALL_BASE;
        minAmount = minAmount * 120 / 100;
    }

    /**
     * @notice Helper function to get weapon name by ID
     * @param weaponID ID of the weapon
     * @return name of the weapon
     */
    function getWeaponName(uint8 weaponID) public pure returns (string memory) {
        Weapon memory weapon = Equipment.getWeapon(weaponID);
        return weapon.name;
    }

    /**
     * @notice Helper function to get weapon by ID
     * @param weaponID ID of the weapon
     * @return weapon
     */
    function getWeapon(uint8 weaponID) public pure returns (Weapon memory) {
        return Equipment.getWeapon(weaponID);
    }

    /**
     * @notice Helper function to get armor name by ID
     * @param armorID ID of the armor
     * @return name of the armor
     */
    function getArmorName(uint8 armorID) public pure returns (string memory) {
        Armor memory armor = Equipment.getArmor(armorID);
        return armor.name;
    }

    /**
     * @notice Helper function to get armor by ID
     * @param armorID ID of the armor
     * @return armor
     */
    function getArmor(uint8 armorID) public pure returns (Armor memory) {
        return Equipment.getArmor(armorID);
    }

    function _getCombatantIDs(bytes32 characterID)
        internal
        view
        returns (bytes32[] memory combatantIDs, uint256 numberOfCombatants)
    {
        BattleNadStats memory stats = _loadBattleNadStats(characterID);

        bytes32 combatantID;
        uint256 combatantBitmap = uint256(stats.combatantBitMap);

        // Filter out the player character
        // NOTE: It should never be in combat with itself - this is tautological
        combatantBitmap &= ~(1 << uint256(stats.index));

        bytes32[] memory combatantIDsUncompressed = new bytes32[](64);

        uint256 i;
        uint256 j;
        for (; i < 64; i++) {
            uint256 indexBit = 1 << i;
            if (combatantBitmap & indexBit != 0) {
                combatantID = areaCombatants[stats.depth][stats.x][stats.y][i];
                if (combatantID != bytes32(0)) {
                    combatantIDsUncompressed[j] = combatantID;
                    ++j;
                }
            }
        }

        numberOfCombatants = j;
        combatantIDs = new bytes32[](j);

        i = 0;
        j = 0;
        for (; i < 64; i++) {
            combatantID = combatantIDsUncompressed[i];
            if (combatantID != bytes32(0)) {
                combatantIDs[j] = combatantID;
                ++j;
            }
        }

        return (combatantIDs, numberOfCombatants);
    }

    function _getNonCombatantIDs(bytes32 characterID)
        internal
        view
        returns (bytes32[] memory nonCombatantIDs, uint256 numberOfNonCombatants)
    {
        BattleNadStats memory stats = _loadBattleNadStats(characterID);

        bytes32[] memory nonCombatantIDsUncompressed = new bytes32[](64);
        BattleArea memory area = _loadArea(stats.depth, stats.x, stats.y);

        uint256 combatantBitmap = uint256(stats.combatantBitMap);
        uint256 combinedBitmap = uint256(area.playerBitMap) | uint256(area.monsterBitMap);

        // Filter out the player character
        combinedBitmap &= ~(1 << uint256(stats.index));

        uint256 j;
        for (uint256 i; i < 64; i++) {
            uint256 indexBit = 1 << i;
            if (combinedBitmap & indexBit != 0) {
                if (combatantBitmap & indexBit == 0) {
                    bytes32 nonCombatantID = areaCombatants[stats.depth][stats.x][stats.y][i];
                    nonCombatantIDsUncompressed[i] = nonCombatantID;
                    ++j;
                }
            }
        }

        numberOfNonCombatants = j;
        nonCombatantIDs = new bytes32[](j);

        j = 0;
        for (uint256 i; i < 64; i++) {
            bytes32 nonCombatantID = nonCombatantIDsUncompressed[i];
            if (nonCombatantID != bytes32(0)) {
                nonCombatantIDs[j] = nonCombatantID;
                ++j;
            }
        }

        return (nonCombatantIDs, numberOfNonCombatants);
    }

    // FOR THE LOVE OF ALL THAT IS GOOD, DO NOT CALL THIS ON CHAIN!
    function _getCombatantBattleNads(bytes32 characterID) internal view returns (BattleNadLite[] memory combatants) {
        (bytes32[] memory combatantIDs, uint256 length) = _getCombatantIDs(characterID);

        combatants = new BattleNadLite[](length);

        for (uint256 i; i < length; i++) {
            bytes32 combatantID = combatantIDs[i];
            combatants[i] = getBattleNadLite(combatantID);
        }

        return combatants;
    }

    function _getNonCombatantBattleNads(bytes32 characterID)
        internal
        view
        returns (BattleNadLite[] memory nonCombatants)
    {
        (bytes32[] memory nonCombatantIDs, uint256 length) = _getNonCombatantIDs(characterID);

        nonCombatants = new BattleNadLite[](length);

        for (uint256 i; i < length; i++) {
            bytes32 nonCombatantID = nonCombatantIDs[i];
            nonCombatants[i] = getBattleNadLite(nonCombatantID);
        }

        return nonCombatants;
    }

    /**
     * @notice Get weapons that a character can equip
     * @param characterID ID of the character
     * @return weaponIDs Array of equippable weapon IDs
     * @return weaponNames Array of weapon names
     * @return currentWeaponID Currently equipped weapon ID
     */
    function _getEquippableWeapons(bytes32 characterID)
        internal
        view
        returns (uint8[] memory weaponIDs, string[] memory weaponNames, uint8 currentWeaponID)
    {
        BattleNad memory character = getBattleNad(characterID);
        Inventory memory inv = character.inventory;
        currentWeaponID = character.stats.weaponID;

        // Count available weapons
        uint256 weaponCount = 0;
        for (uint8 i = 0; i < 64; i++) {
            if (inv.weaponBitmap & (1 << i) != 0) {
                weaponCount++;
            }
        }

        // Initialize arrays
        weaponIDs = new uint8[](weaponCount);
        weaponNames = new string[](weaponCount);

        // Fill arrays
        uint256 index = 0;
        for (uint8 i = 0; i < 64; i++) {
            if (inv.weaponBitmap & (1 << i) != 0) {
                weaponIDs[index] = i;
                weaponNames[index] = getWeaponName(i);
                index++;
            }
        }

        return (weaponIDs, weaponNames, currentWeaponID);
    }

    /**
     * @notice Get armor that a character can equip
     * @param characterID ID of the character
     * @return armorIDs Array of equippable armor IDs
     * @return armorNames Array of armor names
     * @return currentArmorID Currently equipped armor ID
     */
    function _getEquippableArmor(bytes32 characterID)
        internal
        view
        returns (uint8[] memory armorIDs, string[] memory armorNames, uint8 currentArmorID)
    {
        BattleNad memory character = getBattleNad(characterID);
        Inventory memory inv = character.inventory;
        currentArmorID = character.stats.armorID;

        // Count available armor
        uint256 armorCount = 0;
        for (uint8 i = 0; i < 64; i++) {
            if (inv.armorBitmap & (1 << i) != 0) {
                armorCount++;
            }
        }

        // Initialize arrays
        armorIDs = new uint8[](armorCount);
        armorNames = new string[](armorCount);

        // Fill arrays
        uint256 index = 0;
        for (uint8 i = 0; i < 64; i++) {
            if (inv.armorBitmap & (1 << i) != 0) {
                armorIDs[index] = i;
                armorNames[index] = getArmorName(i);
                index++;
            }
        }

        return (armorIDs, armorNames, currentArmorID);
    }

    function _shortfallToRecommendedBalanceInMON(BattleNad memory player)
        internal
        view
        returns (uint256 netDeficitAmount)
    {
        address sessionKeyAddress = _getSessionKeyAddress(player.owner);

        uint256 sessionKeyDeficitAmount = _sessionKeyBalanceDeficit(sessionKeyAddress);

        uint256 currentBondedShares = _sharesBondedToThis(player.owner);
        uint256 currentBondedAmount = currentBondedShares == 0 ? 0 : _convertWithdrawnShMonToMon(currentBondedShares);

        uint256 recommendedAmount = _getRecommendedBalanceInMON();

        if (currentBondedAmount > sessionKeyDeficitAmount + recommendedAmount) {
            return 0;
        }

        netDeficitAmount = recommendedAmount + sessionKeyDeficitAmount - currentBondedAmount;
        return netDeficitAmount;
    }
}
