//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { CharacterClass, Ability, BattleNadStats, BattleNad } from "./Types.sol";

import { Logs } from "./Logs.sol";
import { Constants } from "./Constants.sol";
import { Errors } from "./libraries/Errors.sol";

import { StatSheet } from "./libraries/StatSheet.sol";

abstract contract Classes is Logs, Constants {
    using StatSheet for BattleNad;

    // NOTE: This should only be called during creation by the factory.
    // NOTE: This function IS designed to MEV-able. Godspeed, fellow searchers.
    function _getPlayerClass(bytes32 characterID) internal view returns (CharacterClass class) {
        bytes32 randomSeed = keccak256(abi.encode(characterID, blockhash(block.number - 1), address(this)));
        uint256 diceRoll = uint256(uint8(0xff) & uint8(uint256(randomSeed >> 200)));
        if (diceRoll < 56) {
            class = CharacterClass.Warrior;
        } else if (diceRoll < 112) {
            class = CharacterClass.Rogue;
        } else if (diceRoll < 168) {
            class = CharacterClass.Monk;
        } else if (diceRoll < 224) {
            class = CharacterClass.Sorcerer;
        } else {
            // Sorry or congrats i guess
            class = CharacterClass.Bard;
        }
    }

    function _getAbility(BattleNad memory attacker, uint256 abilityIndex) internal pure returns (Ability ability) {
        if (attacker.isMonster()) {
            revert Errors.MonstersDontHaveAbilities();
        }

        CharacterClass class = attacker.stats.class;

        if (class == CharacterClass.Bard) {
            if (abilityIndex == 1) {
                ability = Ability.SingSong;
            } else if (abilityIndex == 2) {
                ability = Ability.DoDance;
            } else {
                revert Errors.AbilityDoesntExist();
            }
        } else if (class == CharacterClass.Warrior) {
            if (abilityIndex == 1) {
                ability = Ability.ShieldBash;
            } else if (abilityIndex == 2) {
                ability = Ability.ShieldWall;
            } else {
                revert Errors.AbilityDoesntExist();
            }
        } else if (class == CharacterClass.Rogue) {
            if (abilityIndex == 1) {
                ability = Ability.EvasiveManeuvers;
            } else if (abilityIndex == 2) {
                ability = Ability.ApplyPoison;
            } else {
                revert Errors.AbilityDoesntExist();
            }
        } else if (class == CharacterClass.Monk) {
            if (abilityIndex == 1) {
                ability = Ability.Pray;
            } else if (abilityIndex == 2) {
                ability = Ability.Smite;
            } else {
                revert Errors.AbilityDoesntExist();
            }
        } else if (class == CharacterClass.Sorcerer) {
            if (abilityIndex == 1) {
                ability = Ability.ChargeUp;
            } else if (abilityIndex == 2) {
                ability = Ability.Fireball;
            } else {
                revert Errors.AbilityDoesntExist();
            }
        }
    }

    function _addClassStatAdjustments(BattleNad memory combatant) internal pure override returns (BattleNad memory) {
        if (!combatant.tracker.classStatsAdded) {
            uint256 rawMaxHealth = _maxHealth(combatant.stats);
            uint256 rawHealth = uint256(combatant.stats.health);
            combatant.stats = _handleAddClassStats(combatant.stats);
            uint256 adjMaxHealth = _maxHealth(combatant.stats);

            if (combatant.isInCombat()) {
                uint256 adjHealth = (rawHealth * adjMaxHealth - 1) / rawMaxHealth;
                combatant.stats.health = uint16(adjHealth);
            } else {
                combatant.stats.health = uint16(adjMaxHealth);
            }

            combatant.maxHealth = adjMaxHealth;
            combatant.tracker.classStatsAdded = true;
        }
        return combatant;
    }

    function _removeClassStatAdjustments(BattleNad memory combatant)
        internal
        pure
        override
        returns (BattleNad memory)
    {
        if (combatant.tracker.classStatsAdded) {
            uint256 adjMaxHealth = _maxHealth(combatant.stats);
            uint256 adjHealth = uint256(combatant.stats.health);
            combatant.stats = _handleRemoveClassStats(combatant.stats);
            uint256 rawMaxHealth = _maxHealth(combatant.stats);

            if (combatant.isInCombat()) {
                uint256 rawHealth = (adjHealth * rawMaxHealth + 1) / adjMaxHealth;
                combatant.stats.health = uint16(rawHealth);
            } else {
                combatant.stats.health = uint16(rawMaxHealth);
            }

            combatant.tracker.classStatsAdded = false;
        }
        return combatant;
    }

    function _handleAddClassStats(BattleNadStats memory stats) internal pure returns (BattleNadStats memory) {
        uint8 level = stats.level + 1 - stats.unspentAttributePoints;
        if (stats.class == CharacterClass.Elite) {
            stats.strength += uint8(level / 2 + 1);
            stats.vitality += uint8(level / 2);
            stats.dexterity += uint8(level / 2 + 1);
            stats.quickness += uint8(level / 2);
            stats.sturdiness += uint8(level / 2 + 1);

            // NOTE: Bosses are not meant to be solo-able
        } else if (stats.class == CharacterClass.Boss) {
            stats.strength += uint8(level + 1);
            stats.vitality += uint8(level);
            stats.dexterity += uint8(level + 1);
            stats.quickness += uint8(level / 2 + 1);
            stats.sturdiness += uint8(level + 1);
            stats.luck += uint8(level / 2 + 1);
        } else if (stats.class == CharacterClass.Warrior) {
            stats.strength += uint8(level / 3 + 2);
            stats.vitality += uint8(level / 3 + 2);
            stats.quickness -= uint8(1);
        } else if (stats.class == CharacterClass.Rogue) {
            stats.dexterity += uint8(level / 3 + 2);
            stats.quickness += uint8(level / 3 + 2);
            stats.luck += uint8(level / 4);
            stats.strength -= uint8(1);
        } else if (stats.class == CharacterClass.Monk) {
            stats.sturdiness += uint8(level / 3 + 2);
            stats.luck += uint8(level / 3 + 2);
            stats.dexterity -= uint8(1);
        } else if (stats.class == CharacterClass.Sorcerer) {
            stats.strength -= uint8(1);
            stats.vitality -= uint8(1);
            stats.sturdiness -= uint8(1);
        } else if (stats.class == CharacterClass.Bard) {
            stats.strength -= uint8(1);
            stats.vitality -= uint8(1);
            stats.dexterity -= uint8(1);
            stats.sturdiness -= uint8(1);
            stats.luck -= uint8(1);
            stats.quickness -= uint8(1);
        }
        return stats;
    }

    function _handleRemoveClassStats(BattleNadStats memory stats) internal pure returns (BattleNadStats memory) {
        // Tracking level and levelDelta ensures that we don't reduce by more than we increased if the level
        // changes mid-tx
        uint8 level = stats.level + 1 - stats.unspentAttributePoints;
        if (stats.class == CharacterClass.Elite) {
            stats.strength -= uint8(level / 2 + 1);
            stats.vitality -= uint8(level / 2);
            stats.dexterity -= uint8(level / 2 + 1);
            stats.quickness -= uint8(level / 2);
            stats.sturdiness -= uint8(level / 2 + 1);

            // NOTE: Bosses are not meant to be solo-able
        } else if (stats.class == CharacterClass.Boss) {
            stats.strength -= uint8(level + 1);
            stats.vitality -= uint8(level);
            stats.dexterity -= uint8(level + 1);
            stats.quickness -= uint8(level / 2 + 1);
            stats.sturdiness -= uint8(level + 1);
            stats.luck -= uint8(level / 2 + 1);
        } else if (stats.class == CharacterClass.Warrior) {
            stats.strength -= uint8(level / 3 + 2);
            stats.vitality -= uint8(level / 3 + 2);
            stats.quickness += uint8(1);
        } else if (stats.class == CharacterClass.Rogue) {
            stats.dexterity -= uint8(level / 3 + 2);
            stats.quickness -= uint8(level / 3 + 2);
            stats.luck -= uint8(level / 4);
            stats.strength += uint8(1);
        } else if (stats.class == CharacterClass.Monk) {
            stats.sturdiness -= uint8(level / 3 + 2);
            stats.luck -= uint8(level / 3 + 2);
            stats.dexterity += uint8(1);
        } else if (stats.class == CharacterClass.Sorcerer) {
            stats.strength += uint8(1);
            stats.vitality += uint8(1);
            stats.sturdiness += uint8(1);
        } else if (stats.class == CharacterClass.Bard) {
            stats.strength += uint8(1);
            stats.vitality += uint8(1);
            stats.dexterity += uint8(1);
            stats.sturdiness += uint8(1);
            stats.luck += uint8(1);
            stats.quickness += uint8(1);
        }
        return stats;
    }

    function _classAdjustedMaxHealth(BattleNadStats memory stats, uint256 maxHealth) internal pure returns (uint256) {
        uint256 level = uint256(stats.level) - uint256(stats.unspentAttributePoints);
        if (stats.class == CharacterClass.Elite) {
            maxHealth += ((level * 10) + 100);

            // NOTE: Bosses are not meant to be solo-able
        } else if (stats.class == CharacterClass.Boss) {
            maxHealth += ((level * 150) + 1000);
        } else if (stats.class == CharacterClass.Warrior) {
            maxHealth += ((level * 30) + 50);
        } else if (stats.class == CharacterClass.Rogue) {
            // Rogue gets a free first attack that'll probably be a critical
            // but only when out of combat
            maxHealth -= ((level * 20) + 100);
        } else if (stats.class == CharacterClass.Monk) {
            maxHealth += ((level * 20));
        } else if (stats.class == CharacterClass.Sorcerer) {
            maxHealth -= ((level * 30) + 50);
        } else if (stats.class == CharacterClass.Bard) {
            maxHealth -= ((level * 40) + 100);
        }
        return maxHealth;
    }

    // Return different values for view calls (for frontend data) than when executing
    function isExecuting() internal view returns (bool) {
        return msg.sender == address(this);
    }

    function _maxHealth(BattleNadStats memory stats) internal pure virtual returns (uint256 maxHealth);
}
