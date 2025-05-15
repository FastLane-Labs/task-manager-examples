//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    CharacterClass,
    Ability,
    AbilityTracker,
    StatusEffect,
    BattleNadStats,
    BattleNad,
    BattleInstance,
    Inventory,
    BalanceTracker,
    BattleArea,
    LogType,
    Log
} from "./Types.sol";

import { Classes } from "./Classes.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

abstract contract Abilities is Classes {
    using StatSheet for BattleNad;

    function _processAbility(
        BattleNad memory attacker,
        BattleNad memory defender
    )
        internal
        returns (BattleNad memory, BattleNad memory, bool reschedule, uint256 nextBlock)
    {
        Ability ability = attacker.activeAbility.ability;
        uint8 stage = attacker.activeAbility.stage;
        uint8 nextStage;

        uint256 damage;
        uint256 healed;

        if (ability == Ability.SingSong) {
            // log a log about singing a song
            nextStage = 0;
            reschedule = false;
            nextBlock = 0;
        } else if (ability == Ability.DoDance) {
            // log a log about doing a dance
            nextStage = 0;
            reschedule = false;
            nextBlock = 0;
        } else if (ability == Ability.ShieldBash) {
            if (stage == 1) {
                defender.stats.debuffs |= uint8(1 << (uint256(uint8(StatusEffect.Stunned))));
                nextStage = stage + uint8(1);
                reschedule = true;
                nextBlock = block.number + 24;
                defender.tracker.updateStats = true;

                uint256 defenderHealth = uint256(defender.stats.health);
                damage = 50
                    + (uint256(attacker.stats.level) + uint256(attacker.stats.strength) + uint256(attacker.stats.dexterity))
                        * 10;
                // Only for very very low health values
                if (damage + 2 > defenderHealth) {
                    defender.stats.health = 1;
                } else {
                    defender.stats.health = uint16(defenderHealth - damage);
                }
            } else if (stage == 2) {
                // Status effect is removed during their combat turn
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        } else if (ability == Ability.ShieldWall) {
            if (stage == 1) {
                attacker.stats.buffs |= uint8(1 << uint256(uint8(StatusEffect.ShieldWall)));
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 6;
                attacker.tracker.updateStats = true;
            } else if (stage == 2) {
                attacker.stats.buffs &= ~uint8(1 << uint256(uint8(StatusEffect.ShieldWall)));
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 24;
                attacker.tracker.updateStats = true;
            } else if (stage == 3) {
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        } else if (ability == Ability.EvasiveManeuvers) {
            if (stage == 1) {
                attacker.stats.buffs |= uint8(1 << uint256(uint8(StatusEffect.Evasion)));
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 3;
                attacker.tracker.updateStats = true;
            } else if (stage == 2) {
                attacker.stats.buffs &= ~uint8(1 << uint256(uint8(StatusEffect.Evasion)));
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 18;
                attacker.tracker.updateStats = true;
            } else if (stage == 3) {
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        } else if (ability == Ability.ApplyPoison) {
            if (stage < 7) {
                // apply debuff status effect each round incase there are multiple rogues
                if (stage == 6) {
                    defender.stats.debuffs &= ~uint8(1 << uint256(uint8(StatusEffect.Poisoned)));
                } else {
                    defender.stats.debuffs |= uint8(1 << uint256(uint8(StatusEffect.Poisoned)));
                }

                uint256 defenderHealth = uint256(defender.stats.health);
                damage = (((defenderHealth * 3) + 1) / 75) + 1;
                // Only for very very low health values
                if (damage + 2 > defenderHealth) {
                    defender.stats.health = 1;
                } else {
                    defender.stats.health = uint16(defenderHealth - damage);
                }

                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 4;
                defender.tracker.updateStats = true;
            } else if (stage == 7) {
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 64;
            } else {
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        } else if (ability == Ability.Pray) {
            // TODO: This should put monk in combat with everyone the recipient is in combat with

            if (stage == 1) {
                attacker.stats.buffs |= uint8(1 << uint256(uint8(StatusEffect.Praying)));
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 18;
                attacker.tracker.updateStats = true;
            } else if (stage == 2) {
                attacker.stats.buffs &= ~uint8(1 << uint256(uint8(StatusEffect.Praying)));
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 72; // Long cooldown
                attacker.tracker.updateStats = true;

                // Self heal
                if (attacker.isStunned()) {
                    // A well-timed stun interupts the heal
                } else if (defender.id == bytes32(0)) {
                    uint256 health = uint256(attacker.stats.health);
                    uint256 maxHealth = attacker.maxHealth;
                    healed =
                        (maxHealth / 3) + ((10 + uint256(attacker.stats.luck)) * uint256(attacker.stats.sturdiness));

                    // Being cursed reduces healing
                    if (attacker.isCursed()) {
                        healed /= 5;
                    }

                    // Only for very very low health values
                    if (health + healed > maxHealth) {
                        attacker.stats.health = uint16(maxHealth);
                    } else {
                        attacker.stats.health = uint16(health + healed);
                    }

                    // CASE: Real 'defender' exists - monk is healing someone else
                } else {
                    uint256 health = uint256(defender.stats.health);
                    uint256 maxHealth = defender.maxHealth;
                    healed = (maxHealth / 5) + (attacker.maxHealth / 5)
                        + ((10 + uint256(attacker.stats.luck)) * uint256(defender.stats.sturdiness));

                    // Being cursed reduces healing
                    if (defender.isCursed()) {
                        healed /= 5;
                    }

                    // Only for very very low health values
                    if (health + healed > maxHealth) {
                        defender.stats.health = uint16(maxHealth);
                    } else {
                        defender.stats.health = uint16(health + healed);
                    }

                    defender.tracker.updateStats = true;
                }
            } else if (stage == 3) {
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        } else if (ability == Ability.Smite) {
            if (stage == 1) {
                defender.stats.debuffs |= uint8(1 << uint256(uint8(StatusEffect.Cursed)));

                uint256 defenderHealth = uint256(defender.stats.health);
                damage = 50 + (uint256(attacker.stats.level) + uint256(attacker.stats.luck) - 1) * 10;
                // Only for very very low health values
                if (damage + 2 > defenderHealth) {
                    defender.stats.health = 1;
                } else {
                    defender.stats.health = uint16(defenderHealth - damage);
                }

                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 24;
                defender.tracker.updateStats = true;
            } else if (stage == 2) {
                defender.stats.debuffs &= ~uint8(1 << uint256(uint8(StatusEffect.Cursed)));
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        } else if (ability == Ability.Fireball) {
            if (stage == 1) {
                uint256 defenderHealth = uint256(defender.stats.health);
                damage = 100 + (uint256(attacker.stats.level) * 30) + (defenderHealth / 6);
                // Only for very very low health values
                if (damage + 2 > defenderHealth) {
                    defender.stats.health = 1;
                } else {
                    defender.stats.health = uint16(defenderHealth - damage);
                }

                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 56;
                defender.tracker.updateStats = true;
            } else if (stage == 2) {
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        } else if (ability == Ability.ChargeUp) {
            if (stage < 4) {
                if (stage == 1) {
                    attacker.stats.buffs |= uint8(1 << uint256(uint8(StatusEffect.ChargingUp)));
                    attacker.tracker.updateStats = true;
                }
                if (attacker.isStunned()) {
                    // A well-timed stun interupts the charge up
                    nextStage = 6;
                    reschedule = true;
                    nextBlock = block.number + 72;
                } else {
                    nextStage = stage + 1;
                    reschedule = true;
                    nextBlock = block.number + 8;
                }
            } else if (stage == 4) {
                attacker.stats.buffs &= ~uint8(1 << uint256(uint8(StatusEffect.ChargingUp)));
                attacker.stats.buffs |= uint8(1 << uint256(uint8(StatusEffect.ChargedUp)));
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 72;
                attacker.tracker.updateStats = true;
            } else if (stage == 5) {
                if (attacker.isChargedUp()) {
                    attacker.stats.buffs &= ~uint8(1 << uint256(uint8(StatusEffect.ChargedUp)));
                    attacker.tracker.updateStats = true;
                }
                nextStage = stage + 1;
                reschedule = true;
                nextBlock = block.number + 36;
            } else if (stage == 6) {
                if (attacker.isChargingUp()) {
                    attacker.stats.buffs &= ~uint8(1 << uint256(uint8(StatusEffect.ChargingUp)));
                    attacker.tracker.updateStats = true;
                }
                if (attacker.isChargedUp()) {
                    attacker.stats.buffs &= ~uint8(1 << uint256(uint8(StatusEffect.ChargedUp)));
                    attacker.tracker.updateStats = true;
                }
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            } else {
                nextStage = 0;
                reschedule = false;
                nextBlock = 0;
            }
        }
        {
            // Log the ability occurence
            _logAbility(attacker, defender, ability, stage, damage, healed, nextBlock);

            // Tag to update ability tracking
            attacker.tracker.updateActiveAbility = true;

            // Update tracking
            attacker.activeAbility.stage = nextStage;
            attacker.activeAbility.targetBlock = uint64(nextBlock);
            if (!reschedule) {
                attacker.activeAbility.taskAddress = address(0);
                attacker.activeAbility.ability = Ability.None;
                attacker.activeAbility.targetIndex = uint8(0);
            }
        }

        // Return values
        return (attacker, defender, reschedule, nextBlock);
    }

    function _isOffensiveAbility(Ability ability) internal pure returns (bool isOffensive) {
        isOffensive = ability == Ability.ApplyPoison || ability == Ability.Fireball || ability == Ability.ShieldBash
            || ability == Ability.Smite || ability == Ability.DoDance;
    }

    function _checkAbilityTimeout(BattleNad memory attacker) internal view returns (BattleNad memory, bool reset) {
        uint256 targetBlock = uint256(attacker.activeAbility.targetBlock);

        // If an egregious amount of time has passed, unblock abilities
        if (block.number > targetBlock + 200) {
            attacker.activeAbility.stage = uint8(0);
            attacker.activeAbility.targetBlock = uint64(0);
            attacker.activeAbility.taskAddress = address(0);
            attacker.activeAbility.ability = Ability.None;
            attacker.activeAbility.targetIndex = uint8(0);

            // Flag for update
            attacker.tracker.updateActiveAbility = true;
            reset = true;
        }
        return (attacker, reset);
    }
}
