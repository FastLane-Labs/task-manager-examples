//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { BattleNad, BattleNadStats, BattleInstance, BattleArea, StorageTracker, Inventory } from "./Types.sol";

import { Combat } from "./Combat.sol";
import { Errors } from "./libraries/Errors.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { Events } from "./libraries/Events.sol";

abstract contract Instances is Combat {
    using Equipment for BattleNad;
    using Equipment for Inventory;

    function _loadCombatant(BattleArea memory area, uint256 index) internal view returns (BattleNad memory combatant) {
        bytes32 combatantID;
        unchecked {
            combatantID = instances[area.depth][area.x][area.y].combatants[index];
        }
        if (combatantID == bytes32(0)) {
            revert Errors.InvalidTargetIndex(index);
        }
        combatant = _loadBattleNad(combatantID);
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
        uint256 aggroRange = isBossEncounter ? 64 : DEFAULT_AGGRO_RANGE + uint256(player.stats.depth);
        bool canSpawnNewMonsters =
            isBossEncounter ? uint256(area.monsterCount) == 0 : uint256(area.monsterCount) < MAX_MONSTERS_PER_AREA;
        uint256 monsterBitmap = uint256(area.monsterBitMap);
        uint256 combinedBitmap = uint256(area.playerBitMap) | monsterBitmap;
        uint256 index = uint256(player.stats.index);
        uint256 indexBit;

        // See if the player is too high level to generate aggro
        if (aggroRange <= uint256(player.stats.level)) {
            return (0, false);
        }

        if (!isBossEncounter) {
            aggroRange -= uint256(player.stats.level);
            if (aggroRange > MAX_AGGRO_RANGE) aggroRange = MAX_AGGRO_RANGE;
        }

        do {
            // Pre-Increment loop (monster can't be on same index as player)
            unchecked {
                ++index;
                if (index > 63) {
                    index = 1;
                }
            }

            // Find empty spot
            indexBit = 1 << index;

            // CASE: Someone is at that index
            if (combinedBitmap & indexBit != 0) {
                // CASE: A monster is at that index
                if (monsterBitmap & indexBit != 0) {
                    // We're still in aggro range, so aggro it
                    return (uint8(index), false);
                }

                // CASE: Nobody is at that index, so we check to see if we spawn a new mob
                // Make sure we aren't spawning too many mobs
            } else if (canSpawnNewMonsters) {
                uint256 aggroThreshold = DEFAULT_AGGRO_CHANCE + (aggroRange / 2);
                uint256 aggroRoll = uint256(0xff) & uint256(uint8(uint256(randomSeed >> (aggroRange * 8)))) / 2;
                if (aggroRoll < aggroThreshold) {
                    return (uint8(index), true);
                }
            }

            unchecked {
                --aggroRange;
            }
        } while (aggroRange > 0);

        // Default case - no aggro
        return (0, false);
    }

    function _isValidTarget(BattleArea memory area, uint256 index) internal pure returns (bool) {
        uint256 combinedBitmap = uint256(area.playerBitMap) | uint256(area.monsterBitMap);
        return combinedBitmap & 1 << index != 0;
    }

    function _findNextIndex(BattleArea memory area, bytes32 randomSeed) internal view returns (uint8 newIndex) {
        uint256 index = (uint256(0xff) & uint256(uint8(uint256(randomSeed >> 24)))) / 4;
        uint256 combinedBitmap = uint256(area.playerBitMap) | uint256(area.monsterBitMap);
        uint256 indexBit;

        if (index == 0) index = 1;

        do {
            // Increment loop
            unchecked {
                ++index;
                if (index > 63) {
                    index = 1;
                }
            }

            // Find empty spot
            indexBit = 1 << index;
            if (combinedBitmap & indexBit == 0) {
                return uint8(index);
            }
        } while (gasleft() > 100_000);
    }

    function _validateLocationChange(
        BattleNad memory player,
        uint8 newDepth,
        uint8 newX,
        uint8 newY
    )
        internal
        pure
        returns (BattleNad memory)
    {
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

        bytes32 randomSeed;
        if (currentDepth + 1 == nextDepth) {
            // Going Deeper
            randomSeed = keccak256(abi.encode(_DEPTH_SEED, currentDepth, nextDepth));
        } else if (currentDepth == nextDepth + 1) {
            randomSeed = keccak256(abi.encode(_DEPTH_SEED, nextDepth, currentDepth));
        } else {
            revert Errors.InvalidDepthChange(currentDepth, nextDepth);
        }

        uint256 baseX = uint256(uint256(0xff) & uint256(uint8(uint256(randomSeed >> 8)))) + uint256(currentDepth)
            + uint256(nextDepth);
        baseX %= (MAX_DUNGEON_X - 1);
        x = uint8(baseX + 1);

        uint256 baseY = uint256(uint256(0xff) & uint256(uint8(uint256(randomSeed >> 32)))) + uint256(currentDepth)
            + uint256(nextDepth);
        baseY %= (MAX_DUNGEON_Y - 1);
        y = uint8(baseY + 1);
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
}
