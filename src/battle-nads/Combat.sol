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
    CharacterClass,
    StatusEffect
} from "./Types.sol";

import { MonsterFactory } from "./MonsterFactory.sol";

import { Errors } from "./libraries/Errors.sol";
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
        pure
        returns (BattleNad memory, BattleNad memory)
    {
        uint256 attackerBitmap = uint256(attacker.stats.combatantBitMap);
        uint256 defenderBit = 1 << uint256(defender.stats.index);
        if (attackerBitmap & defenderBit != 0) {
            attackerBitmap ^= defenderBit;
            attacker.stats.combatantBitMap = uint64(attackerBitmap);
            --attacker.stats.combatants;
            // NOTE: To prevent chaining, we only decrement sumOfCombatantLevels when combat is over
            if (!attacker.tracker.updateStats) attacker.tracker.updateStats = true;
        }

        if (attacker.stats.nextTargetIndex == defender.stats.index) {
            attacker.stats.nextTargetIndex = 0;
        }

        uint256 defenderBitmap = uint256(defender.stats.combatantBitMap);
        uint256 attackerBit = 1 << uint256(attacker.stats.index);
        if (defenderBitmap & attackerBit != 0) {
            defenderBitmap ^= attackerBit;
            defender.stats.combatantBitMap = uint64(defenderBitmap);
            --defender.stats.combatants;
            // NOTE: To prevent chaining, we only decrement sumOfCombatantLevels when combat is over
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
        uint256 beatriceBitmap = uint256(beatrice.stats.combatantBitMap);
        uint256 sallyBit = 1 << uint256(sally.stats.index);
        if (beatriceBitmap & sallyBit == 0) {
            beatriceBitmap |= sallyBit;
            beatrice.stats.combatantBitMap = uint64(beatriceBitmap);
            ++beatrice.stats.combatants;
            if (!beatrice.isMonster()) {
                beatrice.stats.sumOfCombatantLevels += sally.stats.level;
            }
            if (!beatrice.tracker.updateStats) beatrice.tracker.updateStats = true;
        }

        uint256 sallyBitmap = uint256(sally.stats.combatantBitMap);
        uint256 beatriceBit = 1 << uint256(beatrice.stats.index);
        if (sallyBitmap & beatriceBit == 0) {
            sallyBitmap |= beatriceBit;
            sally.stats.combatantBitMap = uint64(sallyBitmap);
            ++sally.stats.combatants;
            if (!sally.isMonster()) {
                sally.stats.sumOfCombatantLevels += beatrice.stats.level;
            }
            if (!sally.tracker.updateStats) sally.tracker.updateStats = true;
        }

        emit Events.CharactersEnteredCombat(beatrice.areaID(), beatrice.id, sally.id);

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
        if (defender.isMonster()) return true;
        return attacker.stats.level + defender.stats.sumOfCombatantLevels <= defender.stats.level * 2;
    }

    function _notYetInCombat(BattleNad memory attacker, BattleNad memory defender) internal pure returns (bool) {
        return attacker.stats.combatantBitMap & (1 << uint256(defender.stats.index)) == 0;
    }

    function _getTargetIDAndStats(BattleNad memory attacker)
        internal
        view
        returns (BattleNad memory, bytes32 defenderID, BattleNadStats memory defenderStats)
    {
        // Sanity-check the bitmap
        uint256 targetBitmap = uint256(attacker.stats.combatantBitMap);
        if (targetBitmap == 0 || targetBitmap > type(uint64).max) revert Errors.TargetBitmapInvalid(targetBitmap);

        // Declare variables
        uint256 attackerIndex = uint256(attacker.stats.index);
        uint256 targetIndex;

        // See if attacker has selected a specific target
        if (attacker.stats.nextTargetIndex != 0) {
            targetIndex = uint256(attacker.stats.nextTargetIndex);
            if (targetBitmap & 1 << targetIndex != 0) {
                defenderID = instances[attacker.stats.depth][attacker.stats.x][attacker.stats.y].combatants[targetIndex];
                if (defenderID != bytes32(0)) {
                    // Load the defender and make sure defender is in combat with attacker and not a new player
                    // in that slot.
                    defenderStats = _loadBattleNadStats(defenderID);
                    uint256 defenderBitmap = uint256(defenderStats.combatantBitMap);

                    // Check if defender has attacker in combat
                    // NOTE: If the defender dies their combatant bitmap is zero'd out
                    if (defenderBitmap & 1 << attackerIndex != 0) {
                        return (attacker, defenderID, defenderStats);
                    }
                }

                // Defender doesn't have attacker flagged as as an attacker, which means it's a new defender
                // in that location, so clear that slot on the target bitmap and decrement combatants.
                targetBitmap ^= 1 << targetIndex;
                --attacker.stats.combatants;
            }
            // If defenderID is no longer in combat
            attacker.stats.nextTargetIndex = 0;
            attacker.tracker.updateStats = true;
        }

        // Random target selection for in-combat targets
        bytes32 randomSeed = keccak256(abi.encode(_TARGET_SEED, block.number, attacker.id, blockhash(block.number - 1)));
        targetIndex = (uint256(0xff) & uint256(uint8(uint256(randomSeed >> 8)))) / 2;
        if (targetIndex == 0) {
            targetIndex = 1; // No zero index
        } else if (targetIndex > 63) {
            // shouldn't be possible
            targetIndex = 63;
        }

        do {
            // Return early if there are no valid combatants
            if (targetBitmap == 0) {
                defenderID = bytes32(0);
                attacker.stats.combatants = 0;
                attacker.tracker.updateStats = true;
                break;
            }

            // Check if this index is a match
            // TODO: Add skipping mechanism
            if (targetBitmap & 1 << targetIndex != 0) {
                defenderID = instances[attacker.stats.depth][attacker.stats.x][attacker.stats.y].combatants[targetIndex];
                if (defenderID != bytes32(0)) {
                    // Load the defender and make sure defender is in combat with attacker and not a new player
                    // in that slot.
                    defenderStats = _loadBattleNadStats(defenderID);
                    uint256 defenderBitmap = uint256(defenderStats.combatantBitMap);

                    // Break if match is valid
                    if (defenderBitmap & 1 << attackerIndex != 0) {
                        break;
                    }
                }

                // Defender doesn't have attacker flagged as an attacker, which means it's a new defender
                // in that location, so clear that slot on the target bitmap.
                targetBitmap ^= 1 << targetIndex;
                --attacker.stats.combatants;
                attacker.tracker.updateStats = true;
            }

            // Increment loop
            unchecked {
                if (++targetIndex > 63) {
                    targetIndex = 1;
                }
            }
        } while (gasleft() > 60_000);

        if (attacker.tracker.updateStats) {
            if (attacker.stats.combatants == 0) {
                attacker.stats.sumOfCombatantLevels = 0;
                attacker.stats.nextTargetIndex = 0;
                attacker.stats.combatantBitMap = uint64(0);
            } else {
                attacker.stats.combatantBitMap = uint64(targetBitmap);
            }
        }

        return (attacker, defenderID, defenderStats);
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

        // Get max health
        uint256 maxHealth = combatant.maxHealth;
        uint256 currentHealth = uint256(combatant.stats.health);

        // If not in combat, regenerate to max health
        if (combatant.stats.combatants == 0) {
            uint256 recovered = maxHealth > currentHealth ? maxHealth - currentHealth : 0;
            log.healthHealed = uint16(recovered);

            emit Events.CombatHealthRecovered(combatant.areaID(), combatant.id, recovered, maxHealth);

            combatant.stats.health = uint16(maxHealth);
            return (combatant, log);
        }

        // Health regen has to be normalized for the default cooldown to prevent quickness points from
        // giving extreme health regeneration benefits
        uint256 targetHealthRegeneration = uint256(combatant.stats.vitality) * VITALITY_REGEN_MODIFIER;
        uint256 cooldown = _cooldown(combatant.stats);

        if (combatant.isMonster()) {
            targetHealthRegeneration /= 2;
        }

        uint256 adjustedHealthRegeneration = targetHealthRegeneration * cooldown / DEFAULT_TURN_TIME;

        if (combatant.stats.class == CharacterClass.Monk) {
            adjustedHealthRegeneration += (uint256(combatant.stats.level) * 2 + 10);
        } else if (combatant.stats.class == CharacterClass.Bard) {
            adjustedHealthRegeneration = 1;
        }

        if (combatant.isPraying()) {
            adjustedHealthRegeneration *= 2;
        } else if (combatant.isPoisoned()) {
            adjustedHealthRegeneration /= 4;
        } else if (combatant.isCursed()) {
            adjustedHealthRegeneration = 0;
        }

        // Cannot regenerate above max
        if (currentHealth + adjustedHealthRegeneration > maxHealth) {
            uint256 recovered = maxHealth > currentHealth ? maxHealth - currentHealth : 0;

            log.healthHealed = uint16(recovered);

            emit Events.CombatHealthRecovered(combatant.areaID(), combatant.id, recovered, maxHealth);

            currentHealth += recovered;

            combatant.stats.health = uint16(currentHealth);
        } else {
            emit Events.CombatHealthRecovered(
                combatant.areaID(), combatant.id, adjustedHealthRegeneration, currentHealth + adjustedHealthRegeneration
            );

            log.healthHealed = uint16(adjustedHealthRegeneration);

            currentHealth += adjustedHealthRegeneration;

            combatant.stats.health = uint16(currentHealth);
        }

        return (combatant, log);
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
            emit Events.CombatMiss(attacker.areaID(), attacker.id, defender.id);

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

        emit Events.CombatHit(
            attacker.areaID(), attacker.id, defender.id, isCritical, damage, uint256(defender.stats.health)
        );

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
            ((HIT_MOD + uint256(attacker.stats.dexterity)) * (attacker.weapon.accuracy + BASE_ACCURACY))
                + uint256(attacker.stats.luck) + uint256(attacker.stats.quickness)
        ) / HIT_MOD;

        uint256 toEvade = (
            (
                (EVADE_MOD + uint256(defender.stats.dexterity) + uint256(defender.stats.luck))
                    * (defender.armor.flexibility + BASE_FLEXIBILITY)
            ) + uint256(defender.stats.quickness)
        ) / EVADE_MOD;

        if (attacker.isMonster()) {
            toHit = toHit * 4 / 5;
        }

        if (defender.isMonster()) {
            toEvade = toEvade * 4 / 5;
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
            if (defender.isPraying()) {
                isCritical = false;
            }
            if (attacker.isChargedUp()) {
                // Note: damage is doubled, so don't make it a crit
                isCritical = false;
            }
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
            (BASE_OFFENSE + uint256(attacker.stats.strength)) * attacker.weapon.baseDamage
                + uint256(attacker.stats.dexterity)
        ) / BASE_OFFENSE;

        uint256 defense = (
            (BASE_DEFENSE + uint256(defender.stats.sturdiness)) * defender.armor.armorFactor
                + uint256(defender.stats.dexterity)
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
            rawDamage /= 4;
        }
        if (attacker.isPraying()) {
            rawDamage /= 2;
        }
        if (attacker.isChargedUp()) {
            rawDamage *= 2;
        }

        if (attacker.stats.class == CharacterClass.Warrior) {
            if (attacker.isBlocking()) {
                rawDamage = rawDamage /= 2;
            } else {
                rawDamage = rawDamage * 105 / 100;
            }
        }

        if (defender.stats.class == CharacterClass.Bard) {
            rawDamage = rawDamage * 120 / 100;
        }
        if (attacker.stats.class == CharacterClass.Bard) {
            rawDamage = rawDamage * 60 / 100;
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
                rawDamage = rawDamage * 4 / 3;
            }
        }

        if (rawDamage > type(uint16).max) rawDamage = type(uint16).max;

        if (attacker.isMonster()) {
            rawDamage = rawDamage * 2 / 3;
        }

        return uint16(rawDamage);
    }

    function _handleLoot(
        BattleNad memory self,
        BattleNad memory vanquished,
        Log memory log
    )
        internal
        returns (BattleNad memory, Log memory)
    {
        // NOTE: Players and monsters only drop their equipped items
        uint256 vanquishedWeaponBit = 1 << uint256(vanquished.stats.weaponID);
        uint256 weaponBitmap = uint256(self.inventory.weaponBitmap);
        if (weaponBitmap & vanquishedWeaponBit == 0) {
            emit Events.LootedNewWeapon(self.areaID(), self.id, vanquished.stats.weaponID, vanquished.weapon.name);
            weaponBitmap |= vanquishedWeaponBit;
            self.inventory.weaponBitmap = uint64(weaponBitmap);
            self.tracker.updateInventory = true;
            log.lootedWeaponID = vanquished.stats.weaponID;
        }

        uint256 vanquishedArmorBit = 1 << uint256(vanquished.stats.armorID);
        uint256 armorBitmap = uint256(self.inventory.armorBitmap);
        if (armorBitmap & vanquishedArmorBit == 0) {
            emit Events.LootedNewArmor(self.areaID(), self.id, vanquished.stats.armorID, vanquished.armor.name);
            armorBitmap |= vanquishedArmorBit;
            self.inventory.armorBitmap = uint64(armorBitmap);
            self.tracker.updateInventory = true;
            log.lootedArmorID = vanquished.stats.armorID;
        }
        return (self, log);
    }
}
