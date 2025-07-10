//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNad, BattleNadStats, BattleArea, Inventory, StorageTracker, Log, CharacterClass, Ability
} from "./Types.sol";

import { Constants } from "./Constants.sol";
import { Errors } from "./libraries/Errors.sol";
import { Abilities } from "./Abilities.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { Events } from "./libraries/Events.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

import { SessionKey } from "lib/fastlane-contracts/src/common/relay/types/GasRelayTypes.sol";

abstract contract Character is Abilities {
    using Equipment for BattleNad;
    using Equipment for Inventory;
    using StatSheet for BattleNad;

    function _cooldown(BattleNadStats memory stats) internal view returns (uint256 cooldown) {
        uint256 quickness = uint256(stats.quickness) + 1;
        uint256 luck = uint256(stats.luck);

        bytes32 randomSeed =
            keccak256(abi.encode(_COOLDOWN_SEED, block.number, quickness / 2, blockhash(block.number - 1)));

        uint256 cooldownRoll = uint256(0xff) & uint256(randomSeed >> 120);

        // Scale up the seed with level to prevent power creep
        cooldownRoll = (cooldownRoll / 2) + uint256(stats.level);

        cooldown = DEFAULT_TURN_TIME;

        if (quickness * QUICKNESS_BASELINE + luck > cooldownRoll) {
            --cooldown;
        } else if (cooldownRoll < luck + uint256(stats.level)) {
            --cooldown;
        }

        if (quickness * 2 + uint256(stats.dexterity) + luck + uint256(stats.level) > cooldownRoll) {
            --cooldown;
        }

        return cooldown;
    }

    function _maxHealth(BattleNadStats memory stats) internal pure override returns (uint256 maxHealth) {
        uint256 levelFactor = uint256(stats.level) - uint256(stats.unspentAttributePoints);

        if (stats.class == CharacterClass.Basic) {
            maxHealth = MONSTER_HEALTH_BASE + (uint256(stats.vitality) * MONSTER_VITALITY_HEALTH_MODIFIER)
                + (uint256(stats.sturdiness) * STURDINESS_HEALTH_MODIFIER);
        } else if (stats.class == CharacterClass.Elite) {
            maxHealth = HEALTH_BASE + (uint256(stats.vitality) * MONSTER_VITALITY_HEALTH_MODIFIER)
                + (uint256(stats.sturdiness) * STURDINESS_HEALTH_MODIFIER);
        } else if (stats.class == CharacterClass.Boss) {
            maxHealth = HEALTH_BASE + (uint256(stats.vitality) * VITALITY_HEALTH_MODIFIER)
                + (uint256(stats.sturdiness) * STURDINESS_HEALTH_MODIFIER);
            maxHealth = (maxHealth + (levelFactor * 150)) * 4 / 3;
        } else {
            // Player classes
            maxHealth = HEALTH_BASE + (uint256(stats.vitality) * VITALITY_HEALTH_MODIFIER)
                + (uint256(stats.sturdiness) * STURDINESS_HEALTH_MODIFIER);

            if (stats.class == CharacterClass.Warrior) {
                maxHealth += (levelFactor * 30);
            } else if (stats.class == CharacterClass.Rogue) {
                maxHealth -= (levelFactor * 20);
            } else if (stats.class == CharacterClass.Monk) {
                maxHealth += (levelFactor * 10);
            } else if (stats.class == CharacterClass.Sorcerer) {
                maxHealth -= (levelFactor * 20);
            } else if (stats.class == CharacterClass.Bard) {
                maxHealth -= (levelFactor * 40);
            }
        }

        maxHealth += (levelFactor * LEVEL_HEALTH_MODIFIER);

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
            emit Events.LevelUp(victor.areaID(), victor.id, currentLevel);
        }

        return (victor, log);
    }

    function _updatePlayerLevelInArea(BattleNad memory character, uint256 newLevels) internal {
        // Load area only if we're changing it
        BattleArea memory area = _loadArea(character.stats.depth, character.stats.x, character.stats.y);

        area.sumOfPlayerLevels += uint16(newLevels);
        area.update = true;

        _storeArea(area, character.stats.depth, character.stats.x, character.stats.y);

        emit Events.LevelUp(character.areaID(), character.id, character.stats.level);
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

        if (!_isValidID(combatantID)) {
            areaCombatants[newDepth][newX][newY][combatantIndex] = combatant.id;
        } else {
            revert Errors.InvalidLocationIndex(combatantID);
        }

        // Return the combatant struct with updated location
        combatant = _updateLocation(combatant, newDepth, newX, newY, newIndex);

        emit Events.CharacterEnteredArea(combatant.areaID(), combatant.id);

        return (combatant, area);
    }

    function _leaveLocation(
        BattleNad memory combatant,
        BattleArea memory area
    )
        internal
        returns (BattleNad memory, BattleArea memory)
    {
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

        // Update the combatant array
        _clearCombatantArraySlot(combatant.stats.depth, combatant.stats.x, combatant.stats.y, combatant.stats.index);

        return (combatant, area);
    }

    function _leaveLocation(BattleNad memory combatant) internal {
        if (combatant.stats.x == 0 || combatant.stats.y == 0) {
            return;
        }
        // Load the area
        BattleArea memory area = _loadArea(combatant.stats.depth, combatant.stats.x, combatant.stats.y);

        if (!combatant.isDead() && !combatant.isMonster()) {
            area = _logLeftArea(combatant, area);
        }

        (combatant, area) = _leaveLocation(combatant, area);

        // Store the area
        _storeArea(area, combatant.stats.depth, combatant.stats.x, combatant.stats.y);

        emit Events.CharacterLeftArea(combatant.areaID(), combatant.id);
    }

    function _clearCombatantArraySlot(uint8 depth, uint8 x, uint8 y, uint8 combatantIndex) internal {
        areaCombatants[depth][x][y][uint256(combatantIndex)] = _NULL_ID;
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

    function _outOfCombatStatUpdate(BattleNad memory combatant) internal pure returns (BattleNad memory) {
        if (combatant.maxHealth == 0) {
            combatant = _addClassStatAdjustments(combatant);
        }
        combatant.stats.health = uint16(combatant.maxHealth);
        combatant.stats.combatants = 0;
        combatant.stats.sumOfCombatantLevels = 0;
        combatant.stats.nextTargetIndex = 0;
        combatant.stats.combatantBitMap = uint64(0);
        combatant.tracker.updateStats = true;
        return combatant;
    }

    function _exitCombat(BattleNad memory combatant) internal override returns (BattleNad memory) {
        if (combatant.stats.health > 3) {
            combatant = _outOfCombatStatUpdate(combatant);

            combatant.activeTask.taskAddress = _loadActiveTaskAddress(combatant.id);
            if (_isValidAddress(combatant.activeTask.taskAddress)) {
                _clearKey(combatant, combatant.activeTask.taskAddress);
            }
            _clearActiveTask(combatant.id);
            combatant.activeTask.taskAddress = _EMPTY_ADDRESS;
            combatant.tracker.updateActiveTask = false;
        }

        combatant = _checkClearAbility(combatant);

        return combatant;
    }

    function _checkClearAbility(BattleNad memory combatant) internal returns (BattleNad memory) {
        if (
            _isValidAddress(combatant.activeAbility.taskAddress) || combatant.activeAbility.targetBlock > 0
                || combatant.activeAbility.stage > 0
        ) {
            combatant.activeAbility.taskAddress = _EMPTY_ADDRESS;
            combatant.activeAbility.targetBlock = uint64(0);
            combatant.activeAbility.stage = 0;
            combatant.activeAbility.ability = Ability.None;
            _clearAbility(combatant.id);
        }
        return combatant;
    }

    function _createOrRescheduleSpawnTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        virtual
        returns (BattleNad memory, bool success);

    function _createOrRescheduleCombatTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        virtual
        returns (BattleNad memory, bool success);

    function _createOrRescheduleAbilityTask(
        BattleNad memory combatant,
        uint256 targetBlock
    )
        internal
        virtual
        returns (BattleNad memory, bool success);

    function _createOrRescheduleAscendTask(BattleNad memory player) internal virtual returns (BattleNad memory);

    function _checkClearTasks(BattleNad memory combatant)
        internal
        virtual
        returns (bool hasActiveCombatTask, address activeTask);

    function _forceClearTasks(BattleNad memory combatant) internal virtual returns (BattleNad memory);

    function _restartCombatTask(BattleNad memory combatant) internal virtual returns (BattleNad memory, bool);

    function _allocateBalanceInDeath(
        BattleNad memory victor,
        BattleNad memory defeated,
        Log memory log
    )
        internal
        virtual
        returns (BattleNad memory, BattleNad memory, Log memory);

    function _clearKey(BattleNad memory combatant, address activeTask) internal virtual;
}
