//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { BattleNad, BattleNadStats, BattleArea, StorageTracker, Inventory, BalanceTracker } from "./Types.sol";

import { Combat } from "./Combat.sol";
import { Errors } from "./libraries/Errors.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { Events } from "./libraries/Events.sol";

abstract contract Instances is Combat {
    using Equipment for BattleNad;
    using Equipment for Inventory;

    function _loadCombatant(
        uint8 depth,
        uint8 x,
        uint8 y,
        uint256 index
    )
        internal
        view
        override
        returns (BattleNad memory combatant)
    {
        bytes32 combatantID = areaCombatants[depth][x][y][index];
        if (_isValidID(combatantID)) {
            combatant = _loadBattleNad(combatantID, true);
        }
    }

    function _checkForAggro(
        BattleNad memory player,
        BattleArea memory area,
        bytes32 randomSeed,
        uint8 prevDepth
    )
        internal
        pure
        returns (uint8 monsterIndex, bool newMonster)
    {
        // Check if this should spawn a boss
        bool isBossEncounter = prevDepth == player.stats.depth && _isBoss(prevDepth, player.stats.x, player.stats.y);
        uint256 monsterBitmap = uint256(area.monsterBitMap);
        uint256 playerBitmap = uint256(area.playerBitMap);

        // Boss has a reserved index.
        if (isBossEncounter) {
            uint256 bossBit = 1 << RESERVED_BOSS_INDEX;
            if (monsterBitmap & bossBit != 0) {
                return (uint8(RESERVED_BOSS_INDEX), false);
            } else {
                return (uint8(RESERVED_BOSS_INDEX), true);
            }
        }

        uint256 combinedBitmap = playerBitmap | monsterBitmap;
        bool canSpawnNewMonsters =
            isBossEncounter ? uint256(area.monsterCount) == 0 : uint256(area.monsterCount) < MAX_MONSTERS_PER_AREA;
        uint256 aggroRange = isBossEncounter ? 64 : DEFAULT_AGGRO_RANGE + uint256(player.stats.depth);
        uint256 playerIndex = uint256(player.stats.index);

        // See if the player is too high level to generate aggro
        if (aggroRange <= uint256(player.stats.level)) {
            return (0, false);
        }

        if (!isBossEncounter) {
            aggroRange -= uint256(player.stats.level);

            if (player.stats.depth < player.stats.level) {
                aggroRange /= 2;
            } else if (player.stats.depth > player.stats.level) {
                aggroRange += (uint256(player.stats.depth) - uint256(player.stats.level));
            }

            if (aggroRange > MAX_AGGRO_RANGE) aggroRange = MAX_AGGRO_RANGE;
        }

        uint256 targetIndexBit;
        uint256 targetIndex = playerIndex;
        if (targetIndex < 2) targetIndex = 2;

        do {
            // Pre-Increment loop (monster can't be on same index as player)
            unchecked {
                if (++targetIndex > 63) {
                    targetIndex = 2;
                }
            }

            // Find empty spot
            targetIndexBit = 1 << targetIndex;

            // CASE: A monster is at that index
            if (monsterBitmap & targetIndexBit != 0) {
                // We're still in aggro range, so aggro it
                return (uint8(targetIndex), false);

                // CASE: Nobody is at that index, so we check to see if we spawn a new mob
                // Make sure we aren't spawning too many mobs
            } else if (canSpawnNewMonsters && (combinedBitmap & targetIndexBit == 0)) {
                uint256 aggroThreshold = DEFAULT_AGGRO_CHANCE + (aggroRange / 2);
                uint256 aggroRoll = (uint256(0xff) & uint256(uint8(uint256(randomSeed >> (aggroRange * 8))))) / 6;
                if (aggroRoll < aggroThreshold) {
                    return (uint8(targetIndex), true);
                }
            }

            unchecked {
                --aggroRange;
            }
        } while (aggroRange > 0 && targetIndex != playerIndex);

        // Default case - no aggro
        return (0, false);
    }

    function _isValidTarget(BattleArea memory area, uint256 index) internal pure returns (bool) {
        uint256 combinedBitmap = uint256(area.playerBitMap) | uint256(area.monsterBitMap);
        return combinedBitmap & (1 << index) != 0;
    }

    function _findNextIndex(
        BattleArea memory area,
        bytes32 randomSeed
    )
        internal
        view
        override
        returns (uint8 newIndex)
    {
        uint256 index = (uint256(0xff) & uint256(uint8(uint256(randomSeed >> 24)))) / 4;
        uint256 combinedBitmap = uint256(area.playerBitMap) | uint256(area.monsterBitMap);
        uint256 indexBit;

        // index 1 is reserved for bosses
        if (index < 2) index = 2;

        do {
            // Increment loop
            unchecked {
                if (++index > 63) {
                    index = 2;
                }
            }

            // Find empty spot
            indexBit = 1 << index;
            if (combinedBitmap & indexBit == 0) {
                return uint8(index);
            }
        } while (true);
    }

    function _validateLocationChange(BattleNad memory player, uint8 newDepth, uint8 newX, uint8 newY) internal pure {
        // Cannot move while in combat
        if (player.stats.combatants != 0) {
            revert Errors.PlayerInCombat();
        }

        // CASE: No Change
        if (newX == player.stats.x && newY == player.stats.y && newDepth == player.stats.depth) {
            revert Errors.InvalidLocationChange(newDepth, newX, newY);

            // CASE: X Change
        } else if (newY == player.stats.y && newDepth == player.stats.depth) {
            if (newX == 0 || newX > MAX_DUNGEON_X) {
                revert Errors.InvalidLocation(newDepth, newX, newY);
            }
            if (newX != player.stats.x + 1 && newX + 1 != player.stats.x) {
                revert Errors.InvalidLocationChange(newDepth, newX, newY);
            }

            // CASE: Y Change
        } else if (newX == player.stats.x && newDepth == player.stats.depth) {
            if (newY == 0 || newY > MAX_DUNGEON_Y) {
                revert Errors.InvalidLocation(newDepth, newX, newY);
            }
            if (newY != player.stats.y + 1 && newY + 1 != player.stats.y) {
                revert Errors.InvalidLocationChange(newDepth, newX, newY);
            }

            // CASE: Depth change
        } else if (newX == player.stats.x && newY == player.stats.y) {
            if (!_canChangeDepth(player, newDepth)) {
                revert Errors.InvalidDepthChange(player.stats.depth, newDepth);
            }

            // CASE: Changing Multiple axis
        } else {
            revert Errors.MultiAxisMovement();
        }
    }

    function _canChangeDepth(BattleNad memory player, uint8 nextDepth) internal pure returns (bool) {
        (uint8 targetX, uint8 targetY) = _depthChangeCoordinates(player.stats.depth, nextDepth);
        return targetX == player.stats.x && targetY == player.stats.y;
    }

    // Can only go deeper into the dungeon at certain coordinates for each level
    function _depthChangeCoordinates(
        uint8 currentDepth,
        uint8 nextDepth
    )
        internal
        pure
        override
        returns (uint8 x, uint8 y)
    {
        if (nextDepth > MAX_DUNGEON_DEPTH || nextDepth == 0) {
            revert Errors.InvalidDepthChange(currentDepth, nextDepth);
        }

        uint256 deeperDepth;
        uint256 shallowerDepth;
        if (currentDepth < nextDepth) {
            shallowerDepth = uint256(currentDepth);
            deeperDepth = uint256(nextDepth);
        } else {
            shallowerDepth = uint256(nextDepth);
            deeperDepth = uint256(currentDepth);
        }

        x = 25; // starting x
        y = 25; // starting y
        // Return (25,25) for location to descend to the second dungeon depth
        if (shallowerDepth == 1) {
            return (x, y);
        }

        uint256 cornerIndicator = shallowerDepth % 4;
        uint8 traverse = uint8(10 + (shallowerDepth / 4));
        // Max depth is 50.
        // 50 > 25 + (10+13) > 25 - (10+13) > 1
        if (cornerIndicator == 0) {
            x -= traverse;
            y -= traverse;
        } else if (cornerIndicator == 1) {
            x += traverse;
            y += traverse;
        } else if (cornerIndicator == 2) {
            x += traverse;
            y -= traverse;
        } else if (cornerIndicator == 3) {
            x -= traverse;
            y += traverse;
        }
        return (x, y);
    }

    // Can only go deeper into the dungeon at certain coordinates for each level
    function _randomSpawnCoordinates(BattleNad memory player)
        internal
        view
        returns (BattleArea memory area, uint8 x, uint8 y)
    {
        // Define variables
        bytes32 randomSeed;
        uint256 threshold = STARTING_OCCUPANT_THRESHOLD;
        uint256 maxOccupants = MAX_COMBATANTS_PER_AREA - 1;

        do {
            // Generate seed
            randomSeed = keccak256(abi.encode(_LOCATION_SPAWN_SEED, threshold, player.id, blockhash(block.number - 1)));

            // Generate X and Y
            uint256 baseX = uint256(uint256(0xff) & uint256(uint8(uint256(randomSeed >> 8))));
            baseX %= (MAX_DUNGEON_X - 1);
            x = uint8(baseX + 1);

            uint256 baseY = uint256(uint256(0xff) & uint256(uint8(uint256(randomSeed >> 32))));
            baseY %= (MAX_DUNGEON_Y - 1);
            y = uint8(baseY + 1);

            // Load area
            unchecked {
                area = _loadArea(1, x, y);
            }

            // Get number of current occupants
            if (uint256(area.playerCount) + uint256(area.monsterCount) < threshold) {
                return (area, x, y);
            }

            // If area is too full, randomly choose another area and increase the acceptable threshold
            unchecked {
                ++threshold;
            }
        } while (gasleft() > 120_000 && threshold < maxOccupants);

        // Return if empty
        BattleArea memory nullArea;
        x = 0;
        y = 0;
        return (nullArea, x, y);
    }

    // Can only go deeper into the dungeon at certain coordinates for each level
    function _unrandomSpawnCoordinates(BattleNad memory player)
        internal
        view
        override
        returns (BattleArea memory area, uint8 x, uint8 y)
    {
        // Generate seed
        bytes32 randomSeed = keccak256(
            abi.encode(_LOCATION_SPAWN_SEED, STARTING_OCCUPANT_THRESHOLD, player.id, blockhash(block.number - 1))
        );

        // Define variables
        uint256 threshold = STARTING_OCCUPANT_THRESHOLD;
        uint256 distancer = (balances.playerCount / (STARTING_OCCUPANT_THRESHOLD * 8)) + 1;
        if (distancer > 20) distancer = 20;
        uint256 maxOccupants = MAX_COMBATANTS_PER_AREA - 1;
        uint256 i = (uint256(0xff) & uint256(randomSeed)) % 8;
        uint256 j = ((uint256(0xff) & uint256(randomSeed >> 32)) % distancer) + 1;
        uint256 baseX = 25;
        uint256 baseY = 25;
        do {
            // Generate X and Y
            if (i % 6 == 0) {
                x = uint8(baseX + j);
                y = uint8(baseY);
            } else if (i % 8 == 1) {
                x = uint8(baseX + j);
                y = uint8(baseY + j);
            } else if (i % 8 == 2) {
                x = uint8(baseX);
                y = uint8(baseY + j);
            } else if (i % 8 == 3) {
                x = uint8(baseX - j);
                y = uint8(baseY + j);
            } else if (i % 8 == 4) {
                x = uint8(baseX - j);
                y = uint8(baseY);
            } else if (i % 8 == 5) {
                x = uint8(baseX - j);
                y = uint8(baseY - j);
            } else if (i % 8 == 6) {
                x = uint8(baseX);
                y = uint8(baseY - j);
            } else if (i % 8 == 7) {
                x = uint8(baseX + j);
                y = uint8(baseY - j);

                // Increment for next loop
                ++threshold;
                ++j;
            }

            // Load area
            area = _loadArea(1, x, y);

            // Get number of current occupants
            if (uint256(area.playerCount) + uint256(area.monsterCount) < threshold) {
                return (area, x, y);
            }

            // If area is too full, randomly choose another area and increase the acceptable threshold
            unchecked {
                ++i;
            }
        } while (gasleft() > 120_000 && threshold < maxOccupants);

        // Return if empty
        BattleArea memory nullArea;
        x = 0;
        y = 0;
        return (nullArea, x, y);
    }

    function _isNoCombatZone(uint8 x, uint8 y, uint8 depth) internal pure returns (bool) {
        return (depth > 1) && (!_isBoss(depth, x, y)) && (x % NO_COMBAT_ZONE_SPACING == 0)
            && (y % NO_COMBAT_ZONE_SPACING == 0);
    }
}
