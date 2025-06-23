//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { SessionKeyData } from "lib/fastlane-contracts/src/common/relay/types/GasRelayTypes.sol";

struct BattleNad {
    bytes32 id;
    BattleNadStats stats;
    uint256 maxHealth;
    Weapon weapon;
    Armor armor;
    Inventory inventory;
    StorageTracker tracker;
    address activeTask;
    AbilityTracker activeAbility;
    address owner;
    string name;
}

// For frontend
struct BattleNadLite {
    bytes32 id;
    CharacterClass class;
    uint256 health;
    uint256 maxHealth;
    uint256 buffs;
    uint256 debuffs;
    uint256 level;
    uint256 index; // location index
    uint256 combatantBitMap;
    Ability ability;
    uint256 abilityStage;
    uint256 abilityTargetBlock;
    string name;
    string weaponName;
    string armorName;
    bool isDead;
}

enum CharacterClass {
    // Null value
    Null,
    // Monsters
    Basic,
    Elite,
    Boss,
    // Player Classes
    Bard,
    Warrior,
    Rogue,
    Monk,
    Sorcerer
}

enum StatusEffect {
    None,
    ShieldWall,
    Evasion,
    Praying,
    ChargingUp,
    ChargedUp,
    Poisoned,
    Cursed,
    Stunned
}

enum Ability {
    None,
    SingSong,
    DoDance,
    ShieldBash,
    ShieldWall,
    EvasiveManeuvers,
    ApplyPoison,
    Pray,
    Smite,
    Fireball,
    ChargeUp
}

struct BattleNadStats {
    // Character Class (3 bytes)
    CharacterClass class;
    uint8 buffs; // bitmap
    uint8 debuffs; // bitmap
    // Current Character Progress Properties (4 bytes)
    uint8 level;
    uint8 unspentAttributePoints; // new levels
    uint16 experience;
    // Buff
    // Character Attributes (6 bytes)
    uint8 strength;
    uint8 vitality;
    uint8 dexterity;
    uint8 quickness;
    uint8 sturdiness;
    uint8 luck;
    // Current location / instance (4 bytes)
    uint8 depth;
    uint8 x;
    uint8 y;
    uint8 index;
    // Inventory (2 bytes)
    uint8 weaponID;
    uint8 armorID;
    // Current Combat Properties (13 bytes)
    uint16 health;
    uint8 sumOfCombatantLevels; // max level is 50, cap is 2x level
    uint8 combatants;
    uint8 nextTargetIndex;
    uint64 combatantBitMap; // Bitmap of combatants in same area that the player is currently in combat with
}

struct BattleArea {
    uint8 playerCount;
    uint16 sumOfPlayerLevels; // impossible to overflow
    uint64 playerBitMap;
    uint8 monsterCount;
    uint16 sumOfMonsterLevels; // impossible to overflow
    uint64 monsterBitMap;
    uint64 lastLogBlock;
    uint8 lastLogIndex;
    bool update;
}

struct Weapon {
    string name;
    uint256 baseDamage;
    uint256 bonusDamage;
    uint256 accuracy;
    uint256 speed;
}

struct Armor {
    string name;
    uint256 armorFactor;
    uint256 armorQuality;
    uint256 flexibility;
    uint256 weight;
}

struct Inventory {
    uint64 weaponBitmap;
    uint64 armorBitmap;
    uint128 balance;
}

struct AbilityTracker {
    Ability ability;
    uint8 stage;
    uint8 targetIndex;
    address taskAddress;
    uint64 targetBlock;
}

struct StorageTracker {
    bool updateStats;
    bool updateInventory;
    bool updateActiveTask;
    bool updateActiveAbility;
    bool updateOwner;
    bool classStatsAdded;
    bool died;
}

struct BalanceTracker {
    uint32 playerCount;
    uint32 playerSumOfLevels;
    uint32 monsterCount;
    uint32 monsterSumOfLevels;
    uint128 monsterSumOfBalances;
}

struct PayoutTracker {
    uint128 boostYieldPayout;
    uint128 ascendPayout;
}

struct FrontendData {
    bytes32 characterID;
    SessionKeyData sessionKeyData;
    BattleNad character;
    BattleNadLite[] combatants;
    BattleNadLite[] noncombatants;
    uint8[] equipableWeaponIDs;
    string[] equipableWeaponNames;
    uint8[] equipableArmorIDs;
    string[] equipableArmorNames;
    DataFeed[] dataFeeds;
    uint256 balanceShortfall;
    uint256 unallocatedAttributePoints;
    uint256 endBlock;
}

enum LogType {
    Combat,
    InstigatedCombat,
    EnteredArea,
    LeftArea,
    Chat,
    Ability,
    Ascend
}

struct Log {
    LogType logType;
    uint16 index;
    uint8 mainPlayerIndex;
    uint8 otherPlayerIndex; // If a monster is spawned for a movement log, this will be the index of the monster
    bool hit;
    bool critical;
    uint16 damageDone;
    uint16 healthHealed;
    bool targetDied;
    uint8 lootedWeaponID;
    uint8 lootedArmorID;
    uint16 experience;
    uint128 value;
}

struct DataFeed {
    uint256 blockNumber;
    Log[] logs;
    string[] chatLogs;
}
