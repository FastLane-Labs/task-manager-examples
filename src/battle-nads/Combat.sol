//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNad,
    BattleNadStats,
    Inventory,
    Weapon,
    Armor,
    StorageTracker,
    Log,
    BattleArea,
    CharacterClass
} from "./Types.sol";

import { MonsterFactory } from "./MonsterFactory.sol";

import { Equipment } from "./libraries/Equipment.sol";

import { Events } from "./libraries/Events.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

abstract contract Combat is MonsterFactory {
    using Equipment for BattleNad;
    using Equipment for Inventory;
    using StatSheet for BattleNad;

    function _isCurrentlyInCombat(
        BattleNad memory attacker,
        BattleNad memory defender
    )
        internal
        pure
        returns (bool attackerInCombat, bool defenderInCombat)
    {
        uint256 attackerBitmap = uint256(attacker.stats.combatantBitMap);
        uint256 defenderBit = 1 << uint256(defender.stats.index);
        uint256 defenderBitmap = uint256(defender.stats.combatantBitMap);
        uint256 attackerBit = 1 << uint256(attacker.stats.index);

        attackerInCombat = attackerBitmap & defenderBit != 0;
        defenderInCombat = defenderBitmap & attackerBit != 0;
    }

    function _disengageFromCombat(
        BattleNad memory attacker,
        BattleNad memory defender
    )
        internal
        returns (BattleNad memory, BattleNad memory)
    {
        uint256 attackerBitmap = uint256(attacker.stats.combatantBitMap);
        uint256 defenderBit = 1 << uint256(defender.stats.index);
        if (attackerBitmap & defenderBit != 0) {
            attackerBitmap &= ~defenderBit;
            attacker.stats.combatantBitMap = uint64(attackerBitmap);
            //if (!attacker.isInCombat()) {
            //    attacker = _exitCombat(attacker);
            //}
            // NOTE: To prevent chaining, we only decrement combatants and sumOfCombatantLevels when combat is over
            if (!attacker.tracker.updateStats) attacker.tracker.updateStats = true;
        }

        if (attacker.stats.nextTargetIndex == defender.stats.index) {
            attacker.stats.nextTargetIndex = 0;
        }

        uint256 defenderBitmap = uint256(defender.stats.combatantBitMap);
        uint256 attackerBit = 1 << uint256(attacker.stats.index);
        if (defenderBitmap & attackerBit != 0) {
            defenderBitmap &= ~attackerBit;
            defender.stats.combatantBitMap = uint64(defenderBitmap);
            //if (!defender.isInCombat()) {
            //    defender = _exitCombat(defender);
            //}
            // NOTE: To prevent chaining, we only decrement combatants and sumOfCombatantLevels when combat is over
            if (!defender.tracker.updateStats) defender.tracker.updateStats = true;
        }

        if (defender.stats.nextTargetIndex == attacker.stats.index) {
            defender.stats.nextTargetIndex = 0;
        }

        return (attacker, defender);
    }

    function _enterMutualCombatToTheDeath(
        BattleNad memory beatrice,
        BattleNad memory sally
    )
        internal
        returns (BattleNad memory, BattleNad memory)
    {
        if (beatrice.isDead() || sally.isDead()) {
            return (beatrice, sally);
        }
        /*
        if (!beatrice.isInCombat()) {
            beatrice = _outOfCombatStatUpdate(beatrice);
        }
        if (!sally.isInCombat()) {
            sally = _outOfCombatStatUpdate(sally);
        }
        */

        if (sally.stats.index == beatrice.stats.index) {
            return (beatrice, sally);
        }

        uint256 beatriceBitmap = uint256(beatrice.stats.combatantBitMap);
        uint256 sallyBit = 1 << uint256(sally.stats.index);
        if (beatriceBitmap & sallyBit == 0) {
            if (beatriceBitmap == 0) {
                beatrice.stats.nextTargetIndex = sally.stats.index;
            }
            beatriceBitmap |= sallyBit;
            beatrice.stats.combatantBitMap = uint64(beatriceBitmap);
            ++beatrice.stats.combatants;
            if (!beatrice.isMonster()) {
                if (uint256(beatrice.stats.sumOfCombatantLevels) + uint256(sally.stats.level) >= type(uint8).max) {
                    beatrice.stats.sumOfCombatantLevels = uint8(type(uint8).max);
                } else {
                    beatrice.stats.sumOfCombatantLevels += sally.stats.level;
                }
            }
            if (!beatrice.tracker.updateStats) beatrice.tracker.updateStats = true;
        }

        uint256 sallyBitmap = uint256(sally.stats.combatantBitMap);
        uint256 beatriceBit = 1 << uint256(beatrice.stats.index);
        if (sallyBitmap & beatriceBit == 0) {
            if (sallyBitmap == 0) {
                sally.stats.nextTargetIndex = beatrice.stats.index;
            }
            sallyBitmap |= beatriceBit;
            sally.stats.combatantBitMap = uint64(sallyBitmap);
            ++sally.stats.combatants;
            if (!sally.isMonster()) {
                if (uint256(sally.stats.sumOfCombatantLevels) + uint256(beatrice.stats.level) >= type(uint8).max) {
                    sally.stats.sumOfCombatantLevels = uint8(type(uint8).max);
                } else {
                    sally.stats.sumOfCombatantLevels += beatrice.stats.level;
                }
            }
            if (!sally.tracker.updateStats) sally.tracker.updateStats = true;
        }

        return (beatrice, sally);
    }

    function _canEnterMutualCombatToTheDeath(
        BattleNad memory attacker,
        BattleNad memory defender
    )
        internal
        pure
        returns (bool)
    {
        if (attacker.isDead() || defender.isDead()) return false;
        if (attacker.stats.index == defender.stats.index) return false;
        if (defender.isMonster()) {
            if (!attacker.isMonster()) {
                return true;
            } else {
                return false;
            }
        }
        if (attacker.isMonster()) {
            if (!defender.isMonster()) {
                return true;
            } else {
                return false;
            }
        }
        return attacker.stats.level + defender.stats.sumOfCombatantLevels <= (defender.stats.level * 2) + 1;
    }

    function _notYetInCombat(BattleNad memory attacker, BattleNad memory defender) internal pure returns (bool) {
        return attacker.stats.combatantBitMap & (1 << uint256(defender.stats.index)) == 0;
    }

    function _getTargetIDAndStats(
        BattleNad memory attacker,
        BattleArea memory area,
        uint8 excludedIndex
    )
        internal
        returns (BattleNad memory, BattleNad memory, BattleArea memory)
    {
        attacker.tracker.updateStats = true;

        // Declare variables
        uint256 combatantBitmap = uint256(attacker.stats.combatantBitMap);
        uint256 attackerIndex = uint256(attacker.stats.index);
        uint256 targetIndex;
        uint256 targetBit;
        bool isBossEncounter = (excludedIndex != uint8(RESERVED_BOSS_INDEX)) && (!attacker.isMonster())
            && (_isBoss(attacker.stats.depth, attacker.stats.x, attacker.stats.y));

        // Sanity check against area bitmap
        uint256 areaBitmap = uint256(area.playerBitMap) | uint256(area.monsterBitMap);

        // Avoid storage load if there's nothing in area bitmap
        combatantBitmap &= areaBitmap;

        // Monsters can attack any player once they're aggro'd but not each other
        if (attacker.isMonster()) {
            combatantBitmap &= uint256(area.playerBitMap);
        }
        // Remove any excluded index
        if (excludedIndex != 0) {
            combatantBitmap &= ~(1 << uint256(excludedIndex));
        }

        // Remove attacker
        combatantBitmap &= ~(1 << attackerIndex);

        if (combatantBitmap == 0) {
            // attacker = _exitCombat(attacker);
            attacker.stats.combatantBitMap = uint64(0);
            attacker.stats.nextTargetIndex = 0;
            BattleNad memory nullDefender;
            return (attacker, nullDefender, area);
        }

        targetIndex = uint256(attacker.stats.nextTargetIndex);
        if (targetIndex < 2) {
            if (isBossEncounter) {
                targetIndex = 1; // uint8(RESERVED_BOSS_INDEX)
            } else {
                targetIndex = 2;
            }
        }

        if (attackerIndex == targetIndex) {
            if (++targetIndex > 64) {
                targetIndex = isBossEncounter ? 1 : 2;
            }
        }

        do {
            targetBit = 1 << targetIndex;

            // Check if this index is a match
            // TODO: Add skipping mechanism
            if (combatantBitmap & targetBit != 0) {
                // Load the defender and make sure defender is in combat with attacker and not a new player
                // in that slot.
                BattleNad memory defender =
                    _loadCombatant(attacker.stats.depth, attacker.stats.x, attacker.stats.y, targetIndex);

                // CASE: defender didnt load
                if (!_isValidID(defender.id)) {
                    area.monsterBitMap = uint64(uint256(area.monsterBitMap) & ~targetBit);
                    area.playerBitMap = uint64(uint256(area.playerBitMap) & ~targetBit);
                    _clearCombatantArraySlot(
                        attacker.stats.depth, attacker.stats.x, attacker.stats.y, uint8(targetIndex)
                    );
                    area.update = true;
                    // Remove from combat

                    // CASE: defender died
                } else if (defender.isDead()) {
                    // Remove from combat
                    if (_isDeadUnaware(defender.id)) {
                        (attacker,, area) = _processDeathDuringKillerTurn(attacker, defender, area);
                        attacker.tracker.updateStats = true;
                    } else if (killMap[defender.id] == attacker.id) {
                        // Not my proudest few lines of code but we're all human and this is a side
                        // project and it's 3am and doing it efficiently would take a long time x.x
                        combatantBitmap &= ~targetBit;
                        attacker.stats.combatantBitMap = uint64(combatantBitmap);
                        _storeBattleNad(attacker);
                        (defender, area) = _processDeathDuringDeceasedTurn(defender, area);
                        attacker = _loadBattleNad(attacker.id, true);
                        attacker.tracker.updateStats = true;
                        defender.id = _NULL_ID;
                        // return early bc we probably dont have much gas left
                        return (attacker, defender, area);
                    } else if (!_isDeadUnprocessed(defender.id)) {
                        area.monsterBitMap = uint64(uint256(area.monsterBitMap) & ~targetBit);
                        area.playerBitMap = uint64(uint256(area.playerBitMap) & ~targetBit);
                        _clearCombatantArraySlot(
                            attacker.stats.depth, attacker.stats.x, attacker.stats.y, uint8(targetIndex)
                        );
                        area.update = true;
                    }

                    // CASE: defender not in combat with attacker
                } else if (uint256(defender.stats.combatantBitMap) & (1 << attackerIndex) == 0) {
                    // Remove from combat

                    // CASE: valid target
                } else {
                    attacker.stats.combatantBitMap = uint64(combatantBitmap);
                    attacker.stats.nextTargetIndex = uint8(targetIndex);
                    return (attacker, defender, area);
                }

                // Remove from bitmap and clear out defender memory struct if it isn't a match
                combatantBitmap &= ~targetBit;
            }
            // Increment loop
            unchecked {
                if (++targetIndex > 64) {
                    targetIndex = isBossEncounter ? 1 : 2;
                }
            }
        } while (combatantBitmap != 0 && gasleft() > 110_000);

        if (combatantBitmap == 0) {
            //attacker = _exitCombat(attacker);
            attacker.stats.combatantBitMap = uint64(0);
            attacker.stats.nextTargetIndex = uint8(0);
        } else {
            attacker.stats.combatantBitMap = uint64(combatantBitmap);
            attacker.stats.nextTargetIndex = uint8(targetIndex);
            if (attacker.stats.nextTargetIndex == attacker.stats.index) {
                if (++attacker.stats.nextTargetIndex > 64) attacker.stats.nextTargetIndex = isBossEncounter ? 1 : 2;
            }
        }
        BattleNad memory nullDefender;
        return (attacker, nullDefender, area);
    }

    function _regenerateHealth(
        BattleNad memory combatant,
        Log memory log
    )
        internal
        returns (BattleNad memory, Log memory)
    {
        // Flag to update if not already exists
        if (!combatant.tracker.updateStats) {
            combatant.tracker.updateStats = true;
        }

        if (combatant.isDead()) {
            return (combatant, log);
        }

        // Get max health
        uint256 maxHealth = combatant.maxHealth;
        if (maxHealth == 0) {
            return (combatant, log);
        }

        uint256 currentHealth = uint256(combatant.stats.health);

        if (currentHealth > maxHealth) {
            combatant.stats.health = uint16(maxHealth);
            return (combatant, log);
        }

        // If not in combat, regenerate to max health
        if (!combatant.isInCombat()) {
            uint256 recovered = maxHealth > currentHealth ? maxHealth - currentHealth : 0;
            log.healthHealed = uint16(recovered);

            // emit Events.CombatHealthRecovered(combatant.areaID(), combatant.id, recovered, maxHealth);

            combatant.stats.health = uint16(maxHealth);
            return (combatant, log);
        }

        // Health regen has to be normalized for the default cooldown to prevent quickness points from
        // giving extreme health regeneration benefits
        uint256 targetHealthRegeneration =
            (uint256(combatant.stats.vitality) + uint256(combatant.stats.level) / 2) * VITALITY_REGEN_MODIFIER;

        if (combatant.isMonster()) {
            if (combatant.stats.class == CharacterClass.Boss) {
                targetHealthRegeneration = targetHealthRegeneration * 3 / 2;
            } else if (combatant.stats.class == CharacterClass.Basic) {
                targetHealthRegeneration = targetHealthRegeneration * 4 / 5;
            } // else: elites have 1:1 regen
        }

        if (combatant.stats.class == CharacterClass.Monk) {
            targetHealthRegeneration = (targetHealthRegeneration * 4 / 3) + ((uint256(combatant.stats.level) + 3) / 3);
        } else if (combatant.stats.class == CharacterClass.Bard) {
            targetHealthRegeneration = 1;
        }

        if (combatant.isPraying()) {
            targetHealthRegeneration = targetHealthRegeneration * 3 / 2;
        } else if (combatant.isPoisoned()) {
            targetHealthRegeneration /= 4;
        } else if (combatant.isCursed()) {
            targetHealthRegeneration = 0;
        }

        targetHealthRegeneration = (targetHealthRegeneration + 2) * HEALING_DILUTION_FACTOR / DAMAGE_DILUTION_BASE;

        // Cannot regenerate above max
        if (currentHealth + targetHealthRegeneration > maxHealth) {
            uint256 recovered = maxHealth > currentHealth ? maxHealth - currentHealth : 0;

            log.healthHealed = uint16(recovered);

            // emit Events.CombatHealthRecovered(combatant.areaID(), combatant.id, recovered, maxHealth);

            currentHealth += recovered;

            combatant.stats.health = uint16(currentHealth);
        } else {
            // emit Events.CombatHealthRecovered(
            //    combatant.areaID(), combatant.id, targetHealthRegeneration, currentHealth + targetHealthRegeneration
            // );

            log.healthHealed = uint16(targetHealthRegeneration);

            currentHealth += targetHealthRegeneration;

            combatant.stats.health = uint16(currentHealth);
        }

        return (combatant, log);
    }

    function _processDeathDuringKillerTurn(
        BattleNad memory attacker,
        BattleNad memory defender,
        BattleArea memory area
    )
        internal
        returns (BattleNad memory, BattleNad memory newDefender, BattleArea memory)
    {
        require(defender.isDead(), "ERR-DefenderAliveCantProcess");
        (attacker, defender) = _disengageFromCombat(attacker, defender);

        _setKiller(defender.id, attacker.id);
        _storeBattleNad(_exitCombat(defender));

        emit Events.PlayerDied(defender.areaID(), defender.id);

        // If attacker is a monster and it just killed a player and it's still in combat,
        // change attacker's owner to another player
        if (attacker.isMonster()) {
            (attacker, newDefender, area) = _getTargetIDAndStats(attacker, area, defender.stats.index);
            if (_isValidID(newDefender.id)) {
                attacker.stats.nextTargetIndex = newDefender.stats.index;
                (attacker, newDefender) = _enterMutualCombatToTheDeath(attacker, newDefender);
            }
        }
        return (attacker, newDefender, area);
    }

    function _processDeathDuringDeceasedTurn(
        BattleNad memory deceased,
        BattleArea memory area
    )
        internal
        returns (BattleNad memory, BattleArea memory)
    {
        // Load the killer's data
        (bytes32 killerID, bool valid) = _getKiller(deceased.id);

        if (valid) {
            BattleNad memory victor;
            if (killerID == _SYSTEM_KILLER) {
                victor.id = _SYSTEM_KILLER;
                victor.stats.class = CharacterClass.Boss;
                victor.stats.health = 2;
                victor.stats.level = deceased.stats.level;
                victor.stats.combatantBitMap = uint64(1 << deceased.stats.index);
                victor.stats.combatants = 1;
                victor.stats.sumOfCombatantLevels = deceased.stats.level;
                victor.maxHealth = 3;
            } else {
                victor = _loadBattleNad(killerID, false);
            }

            Log memory log = _startCombatLog(victor, deceased);
            log.targetDied = true;

            // Monsters don't earn experience or collect loot
            if (!victor.isMonster()) {
                (victor, log) = _earnExperience(victor, deceased.stats.level, deceased.isMonster(), log);
                victor.inventory = inventories[victor.id];
                (victor, log) = _handleLoot(victor, deceased, log);
            }

            (victor, deceased, log) = _allocateBalanceInDeath(victor, deceased, log);

            valid = _finalizeKiller(deceased.id, killerID);

            if (valid && killerID != _SYSTEM_KILLER) {
                // Store victor and log
                area = _storeLog(victor, area, log);
                _storeBattleNad(victor);
            }
        }

        // Remove combatant from location
        (deceased, area) = _leaveLocation(deceased, area);

        // Miscellaneous tracking
        deceased.stats.index = 0;
        deceased.stats.depth = 0;
        deceased.stats.x = 0;
        deceased.stats.y = 0;

        deceased.tracker.updateStats = false;

        _deleteBattleNad(deceased);

        return (deceased, area);
    }

    function _attack(
        BattleNad memory attacker,
        BattleNad memory defender,
        Log memory log
    )
        internal
        returns (BattleNad memory, BattleNad memory, Log memory)
    {
        bytes32 randomSeed =
            keccak256(abi.encode(_COMBAT_SEED, block.number, attacker.id, defender.id, blockhash(block.number - 1)));

        (bool isHit, bool isCritical) = _checkHit(attacker, defender, randomSeed);
        log.hit = isHit;
        log.critical = isCritical;
        if (!isHit) {
            // emit Events.CombatMiss(attacker.areaID(), attacker.id, defender.id);

            return (attacker, defender, log);
        }

        uint16 damage = _getDamage(attacker, defender, randomSeed, isCritical);
        log.damageDone = uint16(damage);
        defender.tracker.updateStats = true;
        if (damage >= defender.stats.health) {
            defender.stats.health = 0;
            defender.tracker.died = true;
        } else {
            defender.stats.health -= damage;
        }

        /*
        emit Events.CombatHit(
            attacker.areaID(), attacker.id, defender.id, isCritical, damage, uint256(defender.stats.health)
        );
        */

        return (attacker, defender, log);
    }

    function _checkHit(
        BattleNad memory attacker,
        BattleNad memory defender,
        bytes32 randomSeed
    )
        internal
        pure
        returns (bool isHit, bool isCritical)
    {
        // "Hit" Modifier
        uint256 toHit = (
            ((HIT_MOD + uint256(attacker.stats.dexterity) * 2) * (attacker.weapon.accuracy + BASE_ACCURACY))
                + uint256(attacker.stats.luck) + uint256(attacker.stats.quickness) + uint256(attacker.stats.level)
        ) / HIT_MOD;

        uint256 toEvade = (
            (
                (EVADE_MOD + uint256(defender.stats.dexterity) + uint256(defender.stats.luck))
                    * (defender.armor.flexibility + BASE_FLEXIBILITY)
            ) + uint256(defender.stats.quickness) + uint256(defender.stats.level) / 2
        ) / EVADE_MOD;

        if (attacker.isMonster()) {
            if (attacker.stats.class == CharacterClass.Boss) {
                toHit = toHit * 4 / 3;
            } else if (attacker.stats.class == CharacterClass.Elite) {
                toHit = toHit * 6 / 5;
            } else {
                toHit = toHit * 7 / 8;
            }
        }

        if (defender.isMonster()) {
            if (defender.stats.class == CharacterClass.Boss) {
                toEvade = toEvade * 6 / 5;
            } else if (defender.stats.class == CharacterClass.Elite) {
                toEvade = toEvade * 9 / 8;
            } else {
                toEvade = toEvade * 8 / 9;
            }
        } else {
            if (defender.stats.class == CharacterClass.Monk) {
                toEvade = toEvade * 6 / 5;
            } else if (defender.stats.class == CharacterClass.Rogue) {
                toEvade = toEvade * 4 / 3;
            }
        }

        if (toHit == 0) toHit = 1;
        if (toEvade == 0) toEvade = 1;

        // NOTE: Low modifiers are good for the attacker
        uint256 hitModifier = TO_HIT_BASE * 100;
        uint256 critModifier = TO_CRITICAL_BASE * 100;
        if (toHit > toEvade) {
            uint256 adjustment = (toHit - toEvade) * 50 / toEvade;
            if (adjustment >= hitModifier) {
                adjustment = hitModifier - 1;
            }
            hitModifier -= adjustment;
            critModifier -= adjustment;
        } else {
            uint256 adjustment = (toEvade - toHit) * 50 / toHit;
            if (adjustment >= hitModifier) {
                adjustment = hitModifier - 1;
            }
            hitModifier += adjustment;
            critModifier += adjustment;
        }

        hitModifier /= 100;
        critModifier /= 100;

        uint256 hitSeed = uint256(0xff) & uint256(uint8(uint256(randomSeed >> 200)));

        if (defender.isEvading()) {
            hitSeed = hitSeed > EVASION_BONUS ? hitSeed - EVASION_BONUS : 0;
        }
        if (defender.isStunned()) {
            hitSeed += STUNNED_PENALTY;
        }

        isHit = hitSeed > hitModifier;
        isCritical = hitSeed > critModifier;
        if (isHit) {
            if (defender.isChargingUp()) {
                isCritical = true;
            }
        }
        if (isCritical) {
            if (defender.isBlocking()) {
                isCritical = false;
            }
            if (attacker.isPraying()) {
                isCritical = false;
            }
            // if (attacker.isChargedUp()) {
            // Note: damage is doubled, so don't make it a crit
            // isCritical = false;
            // }
        }
        if (!isHit && defender.stats.class == CharacterClass.Bard) {
            isHit = true;
            isCritical = true;
        }
        if (isCritical && defender.stats.class == CharacterClass.Bard) {
            isCritical = false;
        }
        return (isHit, isCritical);
    }

    function _getDamage(
        BattleNad memory attacker,
        BattleNad memory defender,
        bytes32 randomSeed,
        bool isCritical
    )
        internal
        pure
        returns (uint16 damage)
    {
        // "Hit" Modifier
        uint256 offense = (
            (BASE_OFFENSE + uint256(attacker.stats.strength) * 2) * attacker.weapon.baseDamage
                + uint256(attacker.stats.dexterity) + uint256(attacker.stats.level)
        ) / BASE_OFFENSE;

        uint256 defense = (
            (BASE_DEFENSE + uint256(defender.stats.sturdiness) * 2) * defender.armor.armorFactor
                + uint256(defender.stats.dexterity) + uint256(defender.stats.level) / 2
        ) / BASE_DEFENSE;

        uint256 offenseSeed = uint256(0xffffffff) & uint256(uint32(uint256(randomSeed >> 32)));
        uint256 offenseRoll =
            offenseSeed % (uint256(attacker.weapon.bonusDamage) + uint256(attacker.stats.luck) / 2 + 2);
        uint256 bonusOffense = offenseRoll
            * (BASE_OFFENSE + uint256(attacker.stats.strength) + uint256(attacker.stats.luck)) / BASE_OFFENSE;
        offense += bonusOffense;

        uint256 defenseSeed = uint256(0xffffffff) & uint256(uint32(uint256(randomSeed >> 96)));
        uint256 defenseRoll =
            defenseSeed % (uint256(defender.armor.armorQuality) + uint256(defender.stats.luck) / 2 + 2);
        uint256 bonusDefense = defenseRoll
            * (BASE_DEFENSE + uint256(defender.stats.sturdiness) + uint256(defender.stats.luck)) / BASE_DEFENSE;
        defense += bonusDefense;

        uint256 rawDamage;
        if (offense > defense) {
            rawDamage = (offense - defense) + defense / 2;
        } else {
            rawDamage = offense / 2;
        }

        if (defender.isBlocking()) {
            if (attacker.stats.class == CharacterClass.Warrior) {
                rawDamage /= 4;
            } else {
                rawDamage /= 3;
            }
        }

        if (attacker.isBlocking()) {
            if (attacker.stats.class == CharacterClass.Warrior) {
                rawDamage = rawDamage * 2 / 3;
            } else {
                rawDamage = rawDamage * 1 / 3;
            }
        }

        if (attacker.isPraying()) {
            rawDamage = rawDamage * 2 / 3;
        }
        if (attacker.isChargedUp()) {
            rawDamage = (rawDamage * 3 / 2) + 10;
        }

        if (attacker.stats.class == CharacterClass.Warrior) {
            if (!attacker.isBlocking()) {
                rawDamage = rawDamage * 110 / 100;
            }
        } else if (attacker.stats.class == CharacterClass.Sorcerer) {
            if (!isCritical) {
                rawDamage = rawDamage * 105 / 100;
            }
        } else if (attacker.stats.class == CharacterClass.Bard) {
            rawDamage = rawDamage * 70 / 100;
        }

        if (defender.stats.class == CharacterClass.Bard) {
            rawDamage = rawDamage * 110 / 100;
        }

        if (isCritical) {
            if (bonusOffense > bonusDefense) {
                rawDamage += ((bonusOffense - bonusDefense) + bonusDefense / 2);
            } else {
                rawDamage += bonusOffense / 2;
            }
            if (attacker.stats.class == CharacterClass.Rogue) {
                rawDamage = rawDamage * 5 / 3;
            } else {
                rawDamage = rawDamage * 9 / 7;
            }

            if (defender.stats.class == CharacterClass.Warrior) {
                rawDamage = rawDamage * 4 / 5;
            } else if (defender.stats.class == CharacterClass.Monk) {
                rawDamage = rawDamage * 7 / 8;
            }
        }

        if (attacker.isMonster()) {
            if (attacker.stats.class == CharacterClass.Boss) {
                rawDamage = rawDamage * 4 / 3;
            } else if (attacker.stats.class == CharacterClass.Elite) {
                rawDamage = rawDamage * 9 / 10;
            } else {
                rawDamage = rawDamage * 3 / 4;
            }
        }

        rawDamage = (rawDamage + uint256(attacker.stats.level) * 2) * DAMAGE_DILUTION_FACTOR / DAMAGE_DILUTION_BASE;
        if (rawDamage > type(uint16).max) rawDamage = type(uint16).max - 1;
        return uint16(rawDamage);
    }

    function _handleLoot(
        BattleNad memory winner,
        BattleNad memory vanquished,
        Log memory log
    )
        internal
        returns (BattleNad memory, Log memory)
    {
        // NOTE: Players and monsters only drop their equipped items... unless youre a bard
        uint256 vanquishedWeaponID = uint256(vanquished.stats.weaponID);
        if (vanquished.isMonster() && winner.stats.class == CharacterClass.Bard) {
            vanquishedWeaponID += (((uint256(MAX_WEAPON_ID) - vanquishedWeaponID) / 5) + 1);
        }

        uint256 vanquishedWeaponBit = 1 << vanquishedWeaponID;
        uint256 weaponBitmap = uint256(winner.inventory.weaponBitmap);
        if (weaponBitmap & vanquishedWeaponBit == 0) {
            // emit Events.LootedNewWeapon(winner.areaID(), winner.id, vanquished.stats.weaponID,
            // vanquished.weapon.name);
            weaponBitmap |= vanquishedWeaponBit;
            winner.inventory.weaponBitmap = uint64(weaponBitmap);
            winner.tracker.updateInventory = true;
            log.lootedWeaponID = vanquished.stats.weaponID;
        }

        uint256 vanquishedArmorID = uint256(vanquished.stats.armorID);
        if (vanquished.isMonster() && winner.stats.class == CharacterClass.Bard) {
            vanquishedArmorID += (((uint256(MAX_ARMOR_ID) - vanquishedArmorID) / 5) + 1);
        }
        uint256 vanquishedArmorBit = 1 << vanquishedArmorID;
        uint256 armorBitmap = uint256(winner.inventory.armorBitmap);
        if (armorBitmap & vanquishedArmorBit == 0) {
            // emit Events.LootedNewArmor(winner.areaID(), winner.id, vanquished.stats.armorID, vanquished.armor.name);
            armorBitmap |= vanquishedArmorBit;
            winner.inventory.armorBitmap = uint64(armorBitmap);
            winner.tracker.updateInventory = true;
            log.lootedArmorID = vanquished.stats.armorID;
        }
        return (winner, log);
    }

    function _loadCombatant(
        uint8 depth,
        uint8 x,
        uint8 y,
        uint256 index
    )
        internal
        view
        virtual
        returns (BattleNad memory combatant);
}
