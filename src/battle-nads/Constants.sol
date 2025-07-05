//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { StatSheet } from "./libraries/StatSheet.sol";

contract Constants {
    // Entrypoint Variables
    uint256 internal constant MIN_EXECUTION_GAS = 850_000;
    uint256 internal constant MOVEMENT_EXTRA_GAS = 400_000;
    uint256 internal constant MIN_REMAINDER_GAS = 65_000;
    uint256 internal constant BASE_TX_GAS_COST = 21_000;
    uint256 internal constant MIN_REMAINDER_GAS_BUFFER = 5000;
    uint256 internal constant BASE_FEE_ADJUSTMENT = 125_000;
    uint256 internal constant BASE_FEE_BASE = 100_000;
    // Combat Variables
    uint256 internal constant STARTING_STAT_SUM = StatSheet.STARTING_STAT_SUM; // 32
    uint8 internal constant MIN_STAT_VALUE = 3;
    uint256 internal constant MAX_STAT_VALUE = 100;
    uint256 internal constant SPAWN_DELAY = 3;

    uint8 internal constant MAX_WEAPON_ID = 64;
    uint8 internal constant MAX_ARMOR_ID = 64;

    uint256 internal constant HEALTH_BASE = 1500;
    uint256 internal constant LEVEL_HEALTH_MODIFIER = 60;
    uint256 internal constant VITALITY_HEALTH_MODIFIER = 100;
    uint256 internal constant VITALITY_REGEN_MODIFIER = 3;
    uint256 internal constant STURDINESS_HEALTH_MODIFIER = 20;

    uint256 internal constant MONSTER_HEALTH_BASE = 1200;
    uint256 internal constant MONSTER_VITALITY_HEALTH_MODIFIER = 60;
    uint256 internal constant MONSTER_STURDINESS_HEALTH_MODIFIER = 40;

    uint256 internal constant DEFAULT_TURN_TIME = 4;
    uint256 internal constant MIN_TURN_TIME = 2;
    uint256 internal constant QUICKNESS_BASELINE = 6;
    uint256 internal constant COMBAT_COLD_START_DELAY_ATTACKER = 3;
    uint256 internal constant COMBAT_COLD_START_DELAY_DEFENDER = 3;
    uint256 internal constant COMBAT_COLD_START_DELAY_MONSTER = 2;

    uint256 internal constant BASE_FLEXIBILITY = 16;
    uint256 internal constant BASE_ACCURACY = 32;
    uint256 internal constant HIT_MOD = 42;
    uint256 internal constant EVADE_MOD = 42;
    uint256 internal constant TO_HIT_BASE = 64;
    uint256 internal constant TO_CRITICAL_BASE = 192;
    uint256 internal constant EVASION_BONUS = 96;
    uint256 internal constant STUNNED_PENALTY = 64;
    uint256 internal constant BASE_OFFENSE = 64;
    uint256 internal constant BASE_DEFENSE = 64; // higher number = bad

    uint256 internal constant MAX_LEVEL = 50;
    uint256 internal constant MIN_LEVEL = 1;
    uint256 internal constant EXP_BASE = 100;
    uint256 internal constant EXP_MOD = 20;
    uint256 internal constant EXP_SCALE = 5;
    uint256 internal constant PVP_EXP_BONUS_FACTOR = 3;

    uint8 internal constant MAX_DUNGEON_DEPTH = 50;
    uint8 internal constant MAX_DUNGEON_X = 50;
    uint8 internal constant MAX_DUNGEON_Y = 50;

    uint256 internal constant MAX_COMBATANTS_PER_AREA = 63; // 0 must stay empty
    uint256 internal constant MAX_MONSTERS_PER_AREA = 32;
    uint256 internal constant DEFAULT_AGGRO_RANGE = 10; // for existing monsters
    uint256 internal constant MAX_AGGRO_RANGE = 16; // for existing monsters
    uint256 internal constant DEFAULT_AGGRO_CHANCE = 16; // out of 128 - spawns a new monster
    uint256 internal constant STARTING_OCCUPANT_THRESHOLD = 16;
    uint8 internal constant NO_COMBAT_ZONE_SPACING = 5;

    uint256 internal constant DAMAGE_DILUTION_FACTOR = 380;
    uint256 internal constant DAMAGE_DILUTION_BASE = 1000;

    // BALANCES
    uint256 internal constant BUY_IN_AMOUNT = 1e17; // 0.1 shMON buyin
    uint256 internal constant MIN_BONDED_AMOUNT = 1e17; // 0.25 shMON min bonded amount
    uint256 internal constant TASK_COMMIT_RESERVE_FACTOR = 128;
    uint256 internal constant BALANCE_BASE = 100;
    uint256 internal constant PLAYER_ALLOCATION = 75;
    uint256 internal constant MONSTER_ALLOCATION = 20;

    uint256 internal constant TASK_GAS = 299_000;
    uint256 internal constant TARGET_MIN_TASK_COUNT = 8;
    uint256 internal constant ESCROW_DURATION = 16;
    uint256 internal constant GAS_BUFFER = 30_000;
    uint256 internal constant YIELD_BOOST_FACTOR = 25_000;
    uint256 internal constant YIELD_BOOST_BASE = 100_000;

    uint256 internal constant _MAX_NAME_LENGTH = 18;
    uint256 internal constant _MIN_NAME_LENGTH = 3;
    uint256 internal constant _MAX_CHAT_STRING_LENGTH = 128;

    uint256 internal constant BALANCE_SHORTFALL_FACTOR = 200;
    uint256 internal constant BALANCE_SHORTFALL_BASE = 100;
    uint256 internal constant MAX_ESTIMATED_EXECUTOR_DELAY = 8; // blocks
    uint8 internal constant MAX_ESTIMATED_EXECUTOR_DELAY_UINT8 = uint8(MAX_ESTIMATED_EXECUTOR_DELAY); // blocks
    uint256 internal constant MAX_ESTIMATED_TASK_DELAY = 16; // blocks
    uint8 internal constant MAX_ESTIMATED_TASK_DELAY_UINT8 = uint8(MAX_ESTIMATED_TASK_DELAY); // blocks

    // Randomness Seeds
    bytes4 internal constant _CHARACTER_SEED = 0xf317a40f; // bytes4(keccak256("Character Creation"));
    bytes4 internal constant _MONSTER_SEED = 0x1c80e594; // bytes4(keccak256("Monster Creation"));
    bytes4 internal constant _COMBAT_SEED = 0x0b0f7378; // bytes4(keccak256("Combat"));
    bytes4 internal constant _ID_SEED = 0xe4543ce1; // bytes4(keccak256("Character ID"));
    bytes4 internal constant _NPC_SEED = 0x9b0ee043; // bytes4(keccak256("NPC ID Salt"));
    bytes4 internal constant _TARGET_SEED = 0xaedcdd2c; // bytes4(keccak256("Next Target ID"));
    bytes4 internal constant _DEPTH_SEED = 0x562468a9; // bytes4(keccak256("Increment Depth"));
    bytes4 internal constant _AREA_SEED = 0xfe43176f; // bytes4(keccak256("New Area Index"));
    bytes4 internal constant _MONSTER_LEVEL_SEED = 0x2970490a; // bytes4(keccak256("Monster Level"));
    bytes4 internal constant _MONSTER_AGGRO_SEED = 0x2e11136c; // bytes4(keccak256("Monster Aggro"));
    bytes4 internal constant _LOCATION_SPAWN_SEED = 0x2a639c6e; // bytes4(keccak256("Location Spawn"));
    bytes4 internal constant _COOLDOWN_SEED = 0x70fbe9d5; // bytes4(keccak256("Cooldown"));
}
