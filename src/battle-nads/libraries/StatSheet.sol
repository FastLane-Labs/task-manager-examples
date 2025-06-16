//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    Weapon,
    Armor,
    BattleNad,
    BattleNadLite,
    BattleNadStats,
    Inventory,
    StatusEffect,
    CharacterClass
} from "../Types.sol";

import { Errors } from "./Errors.sol";

library StatSheet {
    uint256 public constant STARTING_STAT_SUM = 32;

    function isInCombat(BattleNad memory self) internal pure returns (bool inCombat) {
        inCombat = uint256(self.stats.combatantBitMap) != 0;
    }

    function isMonster(BattleNad memory self) internal pure returns (bool monstrous) {
        monstrous = self.stats.class == CharacterClass.Basic || self.stats.class == CharacterClass.Elite
            || self.stats.class == CharacterClass.Boss;
    }

    function isMonster(BattleNadLite memory self) internal pure returns (bool monstrous) {
        monstrous = self.class == CharacterClass.Basic || self.class == CharacterClass.Elite
            || self.class == CharacterClass.Boss;
    }

    function isDead(BattleNadStats memory self) internal pure returns (bool dead) {
        dead = self.health < 2;
    }

    function isDead(BattleNad memory self) internal pure returns (bool dead) {
        dead = self.stats.health < 2;
    }

    function isDead(BattleNadLite memory self) internal pure returns (bool dead) {
        dead = self.stats.health < 2;
    }

    function isStunned(BattleNad memory self) internal pure returns (bool stunned) {
        stunned = self.stats.debuffs & (1 << uint256(uint8(StatusEffect.Stunned))) != 0;
    }

    function isBlocking(BattleNad memory self) internal pure returns (bool blocking) {
        blocking = self.stats.buffs & (1 << uint256(uint8(StatusEffect.ShieldWall))) != 0;
    }

    function isPraying(BattleNad memory self) internal pure returns (bool praying) {
        praying = self.stats.buffs & (1 << uint256(uint8(StatusEffect.Praying))) != 0;
    }

    function isCursed(BattleNad memory self) internal pure returns (bool cursed) {
        cursed = self.stats.debuffs & (1 << uint256(uint8(StatusEffect.Cursed))) != 0;
    }

    function isPoisoned(BattleNad memory self) internal pure returns (bool poisoned) {
        poisoned = self.stats.debuffs & (1 << uint256(uint8(StatusEffect.Poisoned))) != 0;
    }

    function isEvading(BattleNad memory self) internal pure returns (bool evading) {
        evading = self.stats.buffs & (1 << uint256(uint8(StatusEffect.Evasion))) != 0;
    }

    function isChargingUp(BattleNad memory self) internal pure returns (bool chargingUp) {
        chargingUp = self.stats.buffs & (1 << uint256(uint8(StatusEffect.ChargingUp))) != 0;
    }

    function isChargedUp(BattleNad memory self) internal pure returns (bool chargedUp) {
        chargedUp = self.stats.buffs & (1 << uint256(uint8(StatusEffect.ChargedUp))) != 0;
    }

    function unallocatedStatPoints(BattleNad memory self) internal pure returns (uint256 unspentAttributePoints) {
        unspentAttributePoints = uint256(self.stats.unspentAttributePoints);
    }

    function sumOfStatPoints(BattleNad memory self) internal pure returns (uint256 spentPoints) {
        spentPoints = uint256(self.stats.strength) + uint256(self.stats.vitality) + uint256(self.stats.dexterity)
            + uint256(self.stats.quickness) + uint256(self.stats.sturdiness) + uint256(self.stats.luck);
    }

    function areaID(uint8 depth, uint8 x, uint8 y) internal pure returns (bytes32 id) {
        id = bytes32(uint256(depth) | (uint256(x) << 8) | (uint256(y) << 16));
    }

    function areaID(BattleNad memory self) internal pure returns (bytes32 id) {
        id = bytes32(uint256(self.stats.depth) | (uint256(self.stats.x) << 8) | (uint256(self.stats.y) << 16));
    }
}
