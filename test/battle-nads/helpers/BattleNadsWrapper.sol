// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { BattleNadsEntrypoint } from "src/battle-nads/Entrypoint.sol";
import { BattleNad, BattleNadLite, DataFeed, Log, LogType, Ability, BattleNadStats } from "src/battle-nads/Types.sol";
import { StatSheet } from "src/battle-nads/libraries/StatSheet.sol";
import { console } from "forge-std/console.sol";

contract BattleNadsWrapper is BattleNadsEntrypoint {
    using StatSheet for BattleNad;
    using StatSheet for BattleNadLite;

    uint256 public immutable START_BLOCK;
    mapping(address => uint256) public lastBlocks;

    constructor(address taskManager, address shMonad) BattleNadsEntrypoint(taskManager, shMonad) {
        START_BLOCK = block.number;
    }

    function loadBattleNadStats(bytes32 characterID) public view returns (BattleNadStats memory stats) {
        stats = _loadBattleNadStats(characterID);
    }

    function storeBattleNadStats(BattleNadStats memory stats, bytes32 characterID) public {
        _storeBattleNadStats(stats, characterID);
    }

    function getLiteCombatants(address owner) public view returns (BattleNadLite[] memory liteCombatants) {
        (,,, liteCombatants,,,,,,,,) = pollForFrontendData(owner, block.number - 1);
    }

    function getCombatantBattleNads(address owner) public view returns (BattleNad[] memory combatants) {
        BattleNadLite[] memory liteCombatants = getLiteCombatants(owner);
        combatants = new BattleNad[](liteCombatants.length);
        for (uint256 i; i < liteCombatants.length; i++) {
            bytes32 combatantID = liteCombatants[i].id;
            combatants[i] = getBattleNad(combatantID);
        }
        return combatants;
    }

    function printLogs(address owner) public returns (DataFeed[] memory dataFeeds) {
        uint256 startBlock = lastBlocks[owner];
        if (startBlock < START_BLOCK) {
            startBlock = START_BLOCK;
        }
        dataFeeds = getDataFeed(owner, startBlock, block.number);
        lastBlocks[owner] = block.number;

        for (uint256 i = 0; i < dataFeeds.length; i++) {
            DataFeed memory dataFeed = dataFeeds[i];
            if (dataFeed.logs.length > 0) {
                console.log("\nBlock Number:", dataFeed.blockNumber);
                for (uint256 j = 0; j < dataFeed.logs.length; j++) {
                    Log memory logEntry = dataFeed.logs[j];
                    if (logEntry.logType == LogType.Combat) {
                        // Broke down into multiple calls (<= 4 args each)
                        console.log("  Combat:", logEntry.mainPlayerIndex, "->", logEntry.otherPlayerIndex);
                        console.log("    Dmg:", logEntry.damageDone, "Heal:", logEntry.healthHealed);
                        console.log("    Died:", logEntry.targetDied);
                    } else if (logEntry.logType == LogType.InstigatedCombat) {
                        console.log("  InitiateCombat:", logEntry.mainPlayerIndex, "->", logEntry.otherPlayerIndex);
                    } else if (logEntry.logType == LogType.EnteredArea) {
                        console.log("  EnteredArea:", logEntry.mainPlayerIndex);
                    } else if (logEntry.logType == LogType.LeftArea) {
                        console.log("  LeftArea:", logEntry.mainPlayerIndex);
                    } else if (logEntry.logType == LogType.Ability) {
                        // Broke down into multiple calls (<= 4 args each)
                        console.log(
                            "  Ability:", logEntry.mainPlayerIndex, "Type:", uint8(Ability(logEntry.lootedWeaponID))
                        );
                        console.log("    Stage:", logEntry.lootedArmorID, "Dmg:", logEntry.damageDone);
                        console.log("    Heal:", logEntry.healthHealed);
                    } else if (logEntry.logType == LogType.Ascend) {
                        console.log("  Ascend:", logEntry.mainPlayerIndex, "Value:", logEntry.value);
                    }
                }
            }
        }
        return dataFeeds;
    }

    function printBattleNad(BattleNad memory battleNad) public pure {
        console.log("");
        console.log("BattleNad: ", battleNad.name, "id:", uint256(battleNad.id)); // 4 args - OK
        console.log("  Owner:", battleNad.owner); // 2 args - OK
        console.log("  Class:", uint8(battleNad.stats.class)); // 2 args - OK
        // Broke down location log
        console.log("  Location (d,x,y,i):", battleNad.stats.depth, battleNad.stats.x);
        console.log("    ", battleNad.stats.y, battleNad.stats.index);
        // Broke down stats log
        console.log(
            "  Stats (lvl,hp,str,vit):", battleNad.stats.level, battleNad.stats.health, battleNad.stats.strength
        );
        console.log(
            "     (vit,dex,qui,stu):", battleNad.stats.vitality, battleNad.stats.dexterity, battleNad.stats.quickness
        );
        console.log("     (stu,lck):", battleNad.stats.sturdiness, battleNad.stats.luck);
        // Broke down combat log
        console.log("  Combat (tgts,sumLvl):", battleNad.stats.combatants, battleNad.stats.sumOfCombatantLevels);
        console.log("     (map,next):", battleNad.stats.combatantBitMap, battleNad.stats.nextTargetIndex);
        // Broke down equip log (was already ok, but for consistency)
        console.log("  Equip (wep,arm):", battleNad.stats.weaponID, battleNad.stats.armorID); // 4 args - OK
        console.log("  Task:", battleNad.activeTask.taskAddress); // 2 args - OK
        console.log("  Balance:", battleNad.inventory.balance); // 2 args - OK
    }

    // =============================================================================
    // COMBAT FUNCTION TESTING HELPERS
    // =============================================================================

    /**
     * @dev Expose _checkHit for testing hit/miss/critical logic
     */
    function testCheckHit(
        BattleNad memory attacker,
        BattleNad memory defender,
        bytes32 randomSeed
    )
        public
        pure
        returns (bool isHit, bool isCritical)
    {
        return _checkHit(attacker, defender, randomSeed);
    }

    /**
     * @dev Expose _getDamage for testing damage calculation
     */
    function testGetDamage(
        BattleNad memory attacker,
        BattleNad memory defender,
        bytes32 randomSeed,
        bool isCritical
    )
        public
        pure
        returns (uint16 damage)
    {
        return _getDamage(attacker, defender, randomSeed, isCritical);
    }

    /**
     * @dev Expose _canEnterMutualCombatToTheDeath for testing level cap logic
     */
    function testCanEnterMutualCombatToTheDeath(
        BattleNad memory attacker,
        BattleNad memory defender
    )
        public
        pure
        returns (bool)
    {
        return _canEnterMutualCombatToTheDeath(attacker, defender);
    }

    /**
     * @dev Expose _disengageFromCombat for testing combat disengagement
     */
    function testDisengageFromCombat(
        BattleNad memory attacker,
        BattleNad memory defender
    )
        public
        returns (BattleNad memory, BattleNad memory)
    {
        return _disengageFromCombat(attacker, defender);
    }

    /**
     * @dev Expose _regenerateHealth for testing health regeneration
     */
    function testRegenerateHealth(
        BattleNad memory combatant,
        Log memory log
    )
        public
        returns (BattleNad memory, Log memory)
    {
        return _regenerateHealth(combatant, log);
    }

    /**
     * @dev Expose _handleLoot for testing loot distribution
     */
    function testHandleLoot(
        BattleNad memory self,
        BattleNad memory vanquished,
        Log memory log
    )
        public
        returns (BattleNad memory, Log memory)
    {
        return _handleLoot(self, vanquished, log);
    }

    /**
     * @dev Expose _getCombatantIDs for testing combat targeting
     */
    function testGetCombatantIDs(bytes32 characterID)
        public
        view
        returns (bytes32[] memory combatantIDs, uint256 numberOfCombatants)
    {
        return _getCombatantIDs(characterID);
    }

    /**
     * @dev Expose _attack for testing full attack sequence
     */
    function testAttack(
        BattleNad memory attacker,
        BattleNad memory defender,
        Log memory log
    )
        public
        returns (BattleNad memory, BattleNad memory, Log memory)
    {
        return _attack(attacker, defender, log);
    }
}
