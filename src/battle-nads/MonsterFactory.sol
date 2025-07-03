//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { BattleNad, BattleNadStats, Inventory, BalanceTracker, CharacterClass } from "./Types.sol";

import { Constants } from "./Constants.sol";
import { Errors } from "./libraries/Errors.sol";
import { CharacterFactory } from "./CharacterFactory.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { Events } from "./libraries/Events.sol";

abstract contract MonsterFactory is CharacterFactory {
    using Equipment for BattleNad;
    using Equipment for Inventory;

    function _loadExistingMonster(
        BattleNad memory player,
        uint8 monsterIndex
    )
        internal
        view
        returns (BattleNad memory monster)
    {
        // Get Monster ID
        monster.id = areaCombatants[player.stats.depth][player.stats.x][player.stats.y][uint256(monsterIndex)];

        if (!_isValidID(monster.id)) {
            revert Errors.CombatantDoesNotExist(player.stats.depth, player.stats.x, player.stats.y, monsterIndex);
        }

        // Load stats
        monster.stats = _loadBattleNadStats(monster.id);

        if (monster.stats.level == 0) {
            revert Errors.StatSheetDoesNotExist(monster.id);
        }

        // Most recent player to enter combat with the monster is its 'owner'
        address owner = owners[monster.id];
        monster.owner = player.owner;
        if (monster.owner != owner) {
            monster.tracker.updateOwner = true;
        }

        // Return monster
        return monster;
    }

    function _buildNewMonster(BattleNad memory player) internal returns (BattleNad memory monster) {
        // Generate Character ID
        uint256 nonce;
        unchecked {
            nonce = ++monsterNonce;
        }

        monster.id = keccak256(
            abi.encode(
                _NPC_SEED,
                address(this),
                nonce,
                player.id,
                player.stats.y,
                player.stats.depth,
                blockhash(block.number - 1)
            )
        );

        uint256 level;
        CharacterClass class;
        if (_isBoss(player.stats.depth, player.stats.x, player.stats.y)) {
            class = CharacterClass.Boss;
            level = ((uint256(player.stats.depth) * 5) / 4) + 2;
        } else if (uint8(uint256(monster.id)) > 224) {
            class = CharacterClass.Elite;
            level = uint256(player.stats.depth) + 1;
        } else {
            class = CharacterClass.Basic;
            level = _getNewMonsterLevel(player, monster.id);
        }

        // Build character
        // NOTE: Monster inventory isn't stored - they don't change weapons
        monster.stats = _createMonsterStats(monster.id, level, player.stats.depth, class);

        // Flag for storage updates
        monster.tracker.updateStats = true;

        // Update the owner
        monster.owner = player.owner;
        owners[monster.id] = player.owner;
        characterTasks[monster.id] = _NULL_ID;
        killMap[monster.id] = _UNKILLED;

        emit Events.MonsterCreated(monster.id);

        monster.inventory = monster.inventory.addWeaponToInventory(monster.stats.weaponID);
        monster.inventory = monster.inventory.addArmorToInventory(monster.stats.armorID);
        monster.tracker.updateInventory = true;

        // Increment the global balance tracker
        BalanceTracker memory balanceTracker;
        unchecked {
            balanceTracker = balances;
        }

        balanceTracker.monsterSumOfLevels += uint32(level);
        ++balanceTracker.monsterCount;

        unchecked {
            balances = balanceTracker;
        }

        return monster;
    }

    function _createMonsterStats(
        bytes32 monsterID,
        uint256 level,
        uint8 depth,
        CharacterClass class
    )
        internal
        view
        returns (BattleNadStats memory monsterSheet)
    {
        // Assign class
        monsterSheet.class = class;

        // Allocate stat points
        uint8 baseStat = uint8(1 + level / 6);

        monsterSheet.level = uint8(level);
        monsterSheet.strength = uint8(baseStat);
        monsterSheet.vitality = uint8(baseStat);
        monsterSheet.dexterity = uint8(baseStat);
        monsterSheet.quickness = uint8(baseStat);
        monsterSheet.sturdiness = uint8(baseStat);
        monsterSheet.luck = uint8(baseStat);

        uint256 randomSeed = uint256(keccak256(abi.encode(_MONSTER_SEED, monsterID, blockhash(block.number - 1))));

        // Assign stats
        {
            uint256 remainderStat = 3 + (level % 6);
            uint256 i;
            while (remainderStat > 0 && i < 256) {
                uint8 statSeed = uint8(randomSeed >> i);
                if (statSeed > 80) {
                    --remainderStat;
                    if (statSeed > 120) {
                        ++monsterSheet.strength;
                    } else if (statSeed > 112) {
                        ++monsterSheet.vitality;
                    } else if (statSeed > 104) {
                        ++monsterSheet.dexterity;
                    } else if (statSeed > 96) {
                        ++monsterSheet.quickness;
                    } else if (statSeed > 88) {
                        ++monsterSheet.sturdiness;
                    } else {
                        // if (statSeed > 80) {
                        ++monsterSheet.luck;
                    }
                }
                i += 8;
            }
        }

        // Get armor and weapons
        if (class == CharacterClass.Boss) {
            uint8 weaponRoll = uint8(uint256(randomSeed >> 128) % (uint256(depth) / 5 + 2));
            monsterSheet.weaponID = depth + 3 + weaponRoll;
            uint8 armorRoll = uint8(uint256(randomSeed >> 192) % (uint256(depth) / 5 + 2));
            monsterSheet.armorID = depth + 3 + armorRoll;
        } else if (class == CharacterClass.Elite) {
            uint8 weaponRoll = uint8(uint256(randomSeed >> 128) % (uint256(depth) / 8 + 4));
            monsterSheet.weaponID = depth + weaponRoll;
            uint8 armorRoll = uint8(uint256(randomSeed >> 192) % (uint256(depth) / 8 + 4));
            monsterSheet.armorID = depth + armorRoll;
        } else {
            // Get weapon
            uint16 floor = uint16(level) / 2;
            if (floor == 0) floor = 1;
            uint8 weaponID = uint8(floor + uint16(randomSeed >> 128) % uint16(floor));
            if (weaponID == 0) {
                weaponID = 1;
            }

            if (uint256(uint256(0xff) & uint256(uint8(randomSeed >> 160))) > 128) {
                weaponID += 1;
            }

            if (uint256(uint256(0xff) & uint256(uint8(randomSeed >> 192))) > 192) {
                weaponID += 1;
            }

            if (weaponID > MAX_WEAPON_ID) {
                weaponID = MAX_WEAPON_ID;
            }
            monsterSheet.weaponID = weaponID;

            // Get armor
            uint8 armorID = uint8(floor + uint16(randomSeed >> 200) % uint16(floor));
            if (armorID == 0) {
                armorID = 1;
            }

            if (uint256(uint256(0xff) & uint256(uint8(randomSeed >> 216))) > 128) {
                armorID += 1;
            }

            if (uint256(uint256(0xff) & uint256(uint8(randomSeed >> 232))) > 192) {
                armorID += 1;
            }

            if (armorID > MAX_WEAPON_ID) {
                armorID = MAX_WEAPON_ID;
            }
            monsterSheet.armorID = armorID;
        }

        // Fill out with default combat values
        monsterSheet.health = uint16(_maxHealth(monsterSheet));
        monsterSheet.combatants = uint8(0);
        monsterSheet.nextTargetIndex = uint8(0);
        monsterSheet.combatantBitMap = uint64(0);
    }

    function _getNewMonsterLevel(
        BattleNad memory player,
        bytes32 randomSeed
    )
        internal
        pure
        returns (uint8 monsterLevel)
    {
        uint256 levelCap = uint256(player.stats.depth) * 2;
        if (levelCap > MAX_LEVEL) levelCap = MAX_LEVEL;

        uint256 levelFloor = uint256(player.stats.depth) / 2;
        if (levelFloor < MIN_LEVEL) levelFloor = MIN_LEVEL;

        uint256 rawLevel = uint256(0xffff) & uint256(uint16(uint256(randomSeed) >> 48));
        rawLevel = (rawLevel % levelCap) * uint256(player.stats.level) / uint256(player.stats.depth);

        if (rawLevel > levelCap) {
            return uint8(levelCap);
        } else if (rawLevel < levelFloor) {
            return uint8(levelFloor);
        } else {
            return uint8(rawLevel);
        }
    }

    function _isBoss(uint8 currentDepth, uint8 currentX, uint8 currentY) internal pure returns (bool) {
        (uint8 bossX, uint8 bossY) = _depthChangeCoordinates(currentDepth, currentDepth + 1);
        return currentX == bossX && currentY == bossY;
    }

    function _depthChangeCoordinates(
        uint8 currentDepth,
        uint8 nextDepth
    )
        internal
        pure
        virtual
        returns (uint8 x, uint8 y);
}
