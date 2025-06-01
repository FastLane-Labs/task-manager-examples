//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { BattleNad, BattleNadStats, BattleArea, Inventory, StorageTracker, Log, CharacterClass } from "./Types.sol";

import { Constants } from "./Constants.sol";
import { Errors } from "./libraries/Errors.sol";
import { Abilities } from "./Abilities.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { Events } from "./libraries/Events.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

abstract contract Character is Abilities {
    using Equipment for BattleNad;
    using Equipment for Inventory;
    using StatSheet for BattleNad;

    function _cooldown(BattleNadStats memory stats) internal pure returns (uint256 cooldown) {
        uint256 quickness = uint256(stats.quickness) + 1;
        uint256 baseline = QUICKNESS_BASELINE;
        cooldown = DEFAULT_TURN_TIME;
        do {
            if (cooldown < 3) {
                break;
            }
            if (quickness < baseline) {
                if (quickness + uint256(stats.luck) > baseline) {
                    --cooldown;
                }
                break;
            }
            --cooldown;
            baseline = baseline * 3 / 2 + 1;
        } while (cooldown > MIN_TURN_TIME);

        if (
            stats.class == CharacterClass.Basic || stats.class == CharacterClass.Elite
                || stats.class == CharacterClass.Boss
        ) {
            ++cooldown;
        }

        return cooldown;
    }

    function _maxHealth(BattleNadStats memory stats) internal pure override returns (uint256 maxHealth) {
        uint256 baseHealth;
        if (
            stats.class == CharacterClass.Basic || stats.class == CharacterClass.Elite
                || stats.class == CharacterClass.Boss
        ) {
            baseHealth = MONSTER_HEALTH_BASE;
        } else {
            baseHealth = HEALTH_BASE;
        }

        maxHealth = baseHealth + (uint256(stats.vitality) * VITALITY_HEALTH_MODIFIER)
            + (uint256(stats.sturdiness) * STURDINESS_HEALTH_MODIFIER);

        maxHealth += uint256((uint256(stats.level)) * LEVEL_HEALTH_MODIFIER);

        if (
            stats.class == CharacterClass.Basic || stats.class == CharacterClass.Elite
                || stats.class == CharacterClass.Boss
        ) {
            maxHealth = maxHealth * 2 / 3;
        }
        maxHealth = _classAdjustedMaxHealth(stats, maxHealth);
        if (maxHealth > type(uint16).max - 1) maxHealth = type(uint16).max - 1;
    }

    function _earnExperience(
        BattleNad memory victor,
        uint8 levelOfDefeated,
        bool defeatedIsMonster,
        Log memory log
    )
        internal
        returns (BattleNad memory, Log memory)
    {
        // Can't go above max level
        uint256 currentLevel = uint256(victor.stats.level);
        if (currentLevel >= MAX_LEVEL) {
            return (victor, log);
        }

        uint256 defeatedLevel = uint256(levelOfDefeated);

        // Flag to store updated stats
        victor.tracker.updateStats = true;

        // Calculate the XP earned
        uint256 experienceEarned;
        if (defeatedLevel > currentLevel) {
            experienceEarned = EXP_MOD * defeatedLevel * defeatedLevel / currentLevel;
        } else if (defeatedLevel == currentLevel) {
            experienceEarned = EXP_MOD * defeatedLevel;
        } else {
            // if (levelOfDefeated < victor.stats.level)
            experienceEarned = EXP_MOD * defeatedLevel / (1 + currentLevel - defeatedLevel);
        }

        if (!defeatedIsMonster) {
            experienceEarned *= PVP_EXP_BONUS_FACTOR;
        }

        log.experience = uint16(experienceEarned);

        // Load experience already earned
        uint256 currentExperience = uint256(victor.stats.experience);

        // Calculate the total XP needed for next level
        uint256 experienceNeededForNextLevel = (currentLevel * EXP_BASE) + (currentLevel * currentLevel * EXP_SCALE);
        experienceNeededForNextLevel -= currentExperience;

        // Loop through to apply XP to levels
        while (currentLevel < 50) {
            if (experienceEarned < experienceNeededForNextLevel) {
                victor.stats.experience += uint16(experienceEarned);
                break;
            }
            experienceEarned -= experienceNeededForNextLevel;
            ++currentLevel;
            ++victor.stats.unspentAttributePoints;
            experienceNeededForNextLevel = (currentLevel * EXP_BASE) + (currentLevel * currentLevel * EXP_SCALE);
        }

        if (uint256(victor.stats.level) < currentLevel) {
            victor.stats.level = uint8(currentLevel);

            // Handle emission during points allocation to keep task gas low
            // emit Events.LevelUp(victor.areaID(), victor.id, currentLevel);
        }

        return (victor, log);
    }

    function _updatePlayerLevelInArea(BattleNad memory character, uint256 newLevels) internal {
        // Load area only if we're changing it
        BattleArea memory area = _loadArea(character.stats.depth, character.stats.x, character.stats.y);

        area.sumOfPlayerLevels += uint16(newLevels);
        area.update = true;

        _storeArea(area, character.stats.depth, character.stats.x, character.stats.y);

        // emit Events.LevelUp(victor.areaID(), victor.id, currentLevel);
    }

    function _enterLocation(
        BattleNad memory combatant,
        BattleArea memory area,
        uint8 newX,
        uint8 newY,
        uint8 newDepth,
        uint8 newIndex
    )
        internal
        returns (BattleNad memory, BattleArea memory)
    {
        uint256 monsterBitMap = uint256(area.monsterBitMap);
        uint256 playerBitMap = uint256(area.playerBitMap);
        uint256 combinedBitMap = monsterBitMap | playerBitMap;

        if (combatant.isMonster()) {
            area.sumOfMonsterLevels += uint16(combatant.stats.level);
            ++area.monsterCount;

            uint256 monsterBit = 1 << uint256(newIndex);
            if (combinedBitMap & monsterBit == 0) {
                monsterBitMap |= monsterBit;
                area.monsterBitMap = uint64(monsterBitMap);
            } else {
                revert Errors.InvalidLocationBitmap(monsterBitMap, monsterBit);
            }
        } else {
            // Leave the previous area if it isnt a brand new character
            // NOTE: Monsters don't move
            if (combatant.stats.x != 0 && combatant.stats.y == 0) {
                _leaveLocation(combatant);
            }

            // Update the new area
            area.sumOfPlayerLevels += uint16(combatant.stats.level);
            ++area.playerCount;

            uint256 playerBit = 1 << uint256(newIndex);
            if (combinedBitMap & playerBit == 0) {
                playerBitMap |= playerBit;
                area.playerBitMap = uint64(playerBitMap);
            } else {
                revert Errors.InvalidLocationBitmap(playerBitMap, playerBit);
            }
        }

        area.update = true;

        // Update the combatant array
        uint256 combatantIndex = uint256(newIndex);
        bytes32 combatantID = areaCombatants[newDepth][newX][newY][combatantIndex];

        if (combatantID == bytes32(0)) {
            areaCombatants[newDepth][newX][newY][combatantIndex] = combatant.id;
        } else {
            revert Errors.InvalidLocationIndex(combatantID);
        }

        // Return the combatant struct with updated location
        combatant = _updateLocation(combatant, newDepth, newX, newY, newIndex);

        // emit Events.CharacterEnteredArea(combatant.areaID(), combatant.id);

        return (combatant, area);
    }

    function _leaveLocation(BattleNad memory combatant) internal {
        BattleArea memory area = _loadArea(combatant.stats.depth, combatant.stats.x, combatant.stats.y);

        if (combatant.isMonster()) {
            area.sumOfMonsterLevels -= uint16(combatant.stats.level);
            --area.monsterCount;

            uint256 monsterBitMap = uint256(area.monsterBitMap);
            uint256 monsterBit = 1 << uint256(combatant.stats.index);
            if (monsterBitMap & monsterBit != 0) {
                monsterBitMap &= ~monsterBit;
                area.monsterBitMap = uint64(monsterBitMap);
            }
        } else {
            area.sumOfPlayerLevels -= uint16(combatant.stats.level);
            --area.playerCount;

            uint256 playerBitMap = uint256(area.playerBitMap);
            uint256 playerBit = 1 << uint256(combatant.stats.index);
            if (playerBitMap & playerBit != 0) {
                playerBitMap &= ~playerBit;
                area.playerBitMap = uint64(playerBitMap);
            }
        }
        area.update = true;

        // Store the area
        _storeArea(area, combatant.stats.depth, combatant.stats.x, combatant.stats.y);

        // Update the combatant array
        uint256 combatantIndex = uint256(combatant.stats.index);
        bytes32 combatantID =
            areaCombatants[combatant.stats.depth][combatant.stats.x][combatant.stats.y][combatantIndex];

        if (combatantID == combatant.id) {
            areaCombatants[combatant.stats.depth][combatant.stats.x][combatant.stats.y][combatantIndex] = _NULL_ID;
        }

        // emit Events.CharacterLeftArea(combatant.areaID(), combatant.id);
    }

    function _updateLocation(
        BattleNad memory combatant,
        uint8 newDepth,
        uint8 newX,
        uint8 newY,
        uint8 newIndex
    )
        internal
        pure
        returns (BattleNad memory)
    {
        // Update combatant
        combatant.stats.depth = newDepth;
        combatant.stats.x = newX;
        combatant.stats.y = newY;
        combatant.stats.index = newIndex;
        if (!combatant.tracker.updateStats) combatant.tracker.updateStats = true;
        return combatant;
    }

    function _processAttackerDeath(BattleNad memory attacker) internal returns (BattleNad memory) {
        // Store dead character stats for scoreboard
        // _storeDeadBattleNadStats(attacker.stats, attacker.id);

        // Remove combatant from location
        _leaveLocation(attacker);

        // Miscellaneous tracking
        attacker.stats.index = 0;
        attacker.stats.depth = 0;
        attacker.stats.x = 0;
        attacker.stats.y = 0;

        if (attacker.tracker.updateStats) attacker.tracker.updateStats = false;

        _deleteBattleNad(attacker);

        return attacker;
    }

    function _processDefenderDeath(BattleNad memory defender) internal returns (BattleNad memory) {
        // Location handled when it's defender's turn to attack prevent race condition

        // Combat Stats
        defender.stats.health = 0;
        defender.stats.sumOfCombatantLevels = 0;
        defender.stats.combatants = 0;
        defender.stats.nextTargetIndex = 0;
        defender.stats.combatantBitMap = uint64(0);

        if (!defender.tracker.updateStats) defender.tracker.updateStats = true;

        // emit Events.PlayerDied(defender.areaID(), defender.id);

        return defender;
    }

    function _setActiveTask(
        BattleNad memory combatant,
        address newTaskAddress
    )
        internal
        pure
        returns (BattleNad memory)
    {
        if (newTaskAddress != combatant.activeTask) {
            combatant.activeTask = newTaskAddress;
            combatant.tracker.updateActiveTask = true;
        }
        return combatant;
    }

    function _createSpawnTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        virtual
        returns (BattleNad memory, bool success);

    function _createCombatTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        virtual
        returns (BattleNad memory, bool success);

    function _createAbilityTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        virtual
        returns (BattleNad memory, bool success);

    function _createAscendTask(BattleNad memory player) internal virtual returns (BattleNad memory);

    function _allocateBalanceInDeath(
        BattleNad memory victor,
        BattleNad memory defeated,
        Log memory log
    )
        internal
        virtual
        returns (BattleNad memory, BattleNad memory, Log memory);
}
