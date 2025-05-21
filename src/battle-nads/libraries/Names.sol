//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNad,
    BattleNadStats,
    BattleInstance,
    BattleArea,
    StorageTracker,
    Inventory,
    BalanceTracker,
    LogType,
    Log,
    Ability,
    CharacterClass,
    BattleNadLite
} from "../Types.sol";

import { StatSheet } from "./StatSheet.sol";

library Names {
    uint256 private constant _MAX_NAME_LENGTH = 16;
    uint256 private constant _MIN_NAME_LENGTH = 3;

    function addName(BattleNad memory self) internal pure returns (BattleNad memory) {
        if (
            self.stats.class == CharacterClass.Basic || self.stats.class == CharacterClass.Elite
                || self.stats.class == CharacterClass.Boss
        ) {
            string memory unadjustedName = getMonsterName(self.id, self.stats.level);
            self.name = getMonsterNameAdjustment(unadjustedName, self.stats.class, self.stats.level);
        } else if (
            self.stats.class == CharacterClass.Bard || self.stats.class == CharacterClass.Warrior
                || self.stats.class == CharacterClass.Rogue || self.stats.class == CharacterClass.Monk
                || self.stats.class == CharacterClass.Sorcerer
        ) {
            self.name = getPlayerNameAdjustment(self.name, self.stats.class, self.stats.level);
        } else {
            self.name = "MISSING CLASS";
        }
        return self;
    }

    function addName(BattleNadLite memory self) internal pure returns (BattleNadLite memory) {
        if (
            self.class == CharacterClass.Basic || self.class == CharacterClass.Elite
                || self.class == CharacterClass.Boss
        ) {
            string memory unadjustedName = getMonsterName(self.id, uint8(self.level));
            self.name = getMonsterNameAdjustment(unadjustedName, self.class, uint8(self.level));
        } else {
            self.name = getPlayerNameAdjustment(self.name, self.class, uint8(self.level));
        }
        return self;
    }

    function getMonsterNameAdjustment(
        string memory name,
        CharacterClass class,
        uint8 level
    )
        internal
        pure
        returns (string memory)
    {
        if (class == CharacterClass.Basic) {
            return name;
        } else if (class == CharacterClass.Elite) {
            return string.concat("Elite ", name);
        } else if (class == CharacterClass.Boss) {
            if (level < 16) {
                return "Dungeon Floor Boss";
            } else if (level < 24) {
                return string.concat(name, " Boss");
            } else if (level < 24) {
                return string.concat("Dread ", name, " Boss");
            } else if (level < 36) {
                return string.concat("Nightmare ", name, " Boss");
            } else if (level < 48) {
                return string.concat("Infernal ", name, " Boss");
            } else if (level == 46) {
                return "Molandak";
            } else if (level == 47) {
                return "Salmonad";
            } else if (level == 48) {
                return "Abdul";
            } else if (level == 49) {
                return "Fitz";
            } else if (level == 50) {
                return "Tina";
            } else if (level == 51) {
                return "Bill Mondays";
            } else if (level == 52) {
                return "Harpalsinh";
            } else if (level == 53) {
                return "Cookies";
            } else if (level == 54) {
                return "Danny Pipelines";
            } else if (level == 55) {
                return "Port";
            } else if (level == 56) {
                return "Tunez";
            } else if (level == 57) {
                return "John W Rich Kid";
            } else if (level == 58) {
                return "Intern";
            } else if (level == 59) {
                return "James";
            } else if (level == 60) {
                return "Eunice";
            } else if (level > 60) {
                return "Keone";
            }
        }
        return "Monster";
    }

    function getPlayerNameAdjustment(
        string memory name,
        CharacterClass class,
        uint8 level
    )
        internal
        pure
        returns (string memory)
    {
        if (bytes(name).length > _MAX_NAME_LENGTH) {
            name = "Nameless";
        } else if (bytes(name).length < _MIN_NAME_LENGTH) {
            name = "Unnamed";
        }

        if (level < 2) {
            return string.concat(name, " the Initiate");
        }
        if (level < 3) {
            return string.concat(name, " the Trainee");
        }
        if (level < 4) {
            return name;
        }
        if (class == CharacterClass.Bard) {
            if (level < 6) {
                return string.concat(name, " the Unremarkable");
            }
            if (level < 8) {
                return string.concat(name, " the Annoying");
            }
            if (level < 16) {
                return string.concat(name, " the Unfortunate");
            }
            if (level < 32) {
                return string.concat(name, " the Loud");
            }
            if (level < 48) {
                return string.concat(name, " the Unforgettable");
            }
            return string.concat(name, " the Greatest");
        } else if (class == CharacterClass.Warrior) {
            if (level < 6) {
                return string.concat("Sir ", name);
            }
            if (level < 8) {
                return string.concat("Knight ", name);
            }
            if (level < 16) {
                return string.concat("Count ", name);
            }
            if (level < 32) {
                return string.concat("Lord ", name);
            }
            if (level < 48) {
                return string.concat("Duke ", name);
            }
            return string.concat("Hero-King ", name);
        } else if (class == CharacterClass.Rogue) {
            if (level < 6) {
                return string.concat(name, ", Thief");
            }
            if (level < 8) {
                return string.concat(name, ", Infiltrator");
            }
            if (level < 16) {
                return string.concat(name, ", Shadow Blade");
            }
            if (level < 32) {
                return string.concat(name, ", Night Shade");
            }
            if (level < 48) {
                return string.concat(name, ", Chosen of Darkness");
            }
            return string.concat(name, ", King of Thieves");
        } else if (class == CharacterClass.Monk) {
            if (level < 6) {
                return string.concat("Brother ", name);
            }
            if (level < 8) {
                return string.concat("Friar ", name);
            }
            if (level < 16) {
                return string.concat("Father ", name);
            }
            if (level < 32) {
                return string.concat("Bishop ", name);
            }
            if (level < 48) {
                return string.concat("Cardinal ", name);
            }
            return string.concat("Prophet ", name);
        } else if (class == CharacterClass.Sorcerer) {
            if (level < 6) {
                return string.concat(name, " the Student");
            }
            if (level < 8) {
                return string.concat(name, " the Intelligent");
            }
            if (level < 16) {
                return string.concat(name, " the Wise");
            }
            if (level < 32) {
                return string.concat(name, " the Powerful");
            }
            if (level < 48) {
                return string.concat(name, " the Great");
            }
            return name; // at this level, name needs no introduction
        }
        return "Nad";
    }

    function getMonsterName(bytes32 monsterId, uint8 monsterLevel) internal pure returns (string memory monsterName) {
        // First get the name index, which is based on a range around the monster's level. There are 64 possible names.
        uint256 adjustedMonsterLevel = (uint256(monsterLevel) + 1) / 2;
        uint256 monsterNameIndex =
            uint256(0xff & uint8(uint256(monsterId))) % (adjustedMonsterLevel + 4) + adjustedMonsterLevel;

        if (monsterNameIndex < 33) {
            if (monsterNameIndex < 17) {
                // 1 <= monsterNameIndex <= 16
                if (monsterNameIndex < 9) {
                    // 1 <= monsterNameIndex <= 8
                    if (monsterNameIndex < 5) {
                        // 1 <= monsterNameIndex <= 4
                        if (monsterNameIndex == 1) {
                            monsterName = "Slime";
                        } else if (monsterNameIndex == 2) {
                            monsterName = "Jellyfish";
                        } else if (monsterNameIndex == 3) {
                            monsterName = "Dungeon Crab";
                        } else {
                            monsterName = "Cave Bat";
                        }
                    } else {
                        // 5 <= monsterNameIndex <= 8
                        if (monsterNameIndex == 5) {
                            monsterName = "Venomous Snail";
                        } else if (monsterNameIndex == 6) {
                            monsterName = "Spider";
                        } else if (monsterNameIndex == 7) {
                            monsterName = "Cave Viper";
                        } else {
                            monsterName = "Goblin Runt";
                        }
                    }
                } else {
                    // 9 <= monsterNameIndex <= 16
                    if (monsterNameIndex < 13) {
                        // 9 <= monsterNameIndex <= 12
                        if (monsterNameIndex == 9) {
                            monsterName = "Goblin Scout";
                        } else if (monsterNameIndex == 10) {
                            monsterName = "Forest Wolf";
                        } else if (monsterNameIndex == 11) {
                            monsterName = "Skeleton Warrior";
                        } else {
                            monsterName = "Zombie";
                        }
                    } else {
                        // 13 <= monsterNameIndex <= 16
                        if (monsterNameIndex == 13) {
                            monsterName = "Giant Scorpion";
                        } else if (monsterNameIndex == 14) {
                            monsterName = "Hobgoblin";
                        } else if (monsterNameIndex == 15) {
                            monsterName = "Orc";
                        } else {
                            monsterName = "Corrupted Fairy";
                        }
                    }
                }
            } else {
                // 17 <= monsterNameIndex <= 32
                if (monsterNameIndex < 25) {
                    // 17 <= monsterNameIndex <= 24
                    if (monsterNameIndex < 21) {
                        // 17 <= monsterNameIndex <= 20
                        if (monsterNameIndex == 17) {
                            monsterName = "Goblin Shaman";
                        } else if (monsterNameIndex == 18) {
                            monsterName = "Troll";
                        } else if (monsterNameIndex == 19) {
                            monsterName = "Ogre";
                        } else {
                            monsterName = "Ghoul";
                        }
                    } else {
                        // 21 <= monsterNameIndex <= 24
                        if (monsterNameIndex == 21) {
                            monsterName = "Harpy";
                        } else if (monsterNameIndex == 22) {
                            monsterName = "Werewolf";
                        } else if (monsterNameIndex == 23) {
                            monsterName = "Centaur";
                        } else {
                            monsterName = "Minotaur";
                        }
                    }
                } else {
                    // 25 <= monsterNameIndex <= 32
                    if (monsterNameIndex < 29) {
                        // 25 <= monsterNameIndex <= 28
                        if (monsterNameIndex == 25) {
                            monsterName = "Lesser Wyvern";
                        } else if (monsterNameIndex == 26) {
                            monsterName = "Gargoyle";
                        } else if (monsterNameIndex == 27) {
                            monsterName = "Basilisk";
                        } else {
                            monsterName = "Chimera";
                        }
                    } else {
                        // 29 <= monsterNameIndex <= 32
                        if (monsterNameIndex == 29) {
                            monsterName = "Cyclops";
                        } else if (monsterNameIndex == 30) {
                            monsterName = "Manticore";
                        } else if (monsterNameIndex == 31) {
                            monsterName = "Griffin";
                        } else {
                            monsterName = "Hydra";
                        }
                    }
                }
            }
        } else {
            // if monsterNameIndex is 33 or higher, we need to get the name from the second half of the list
            if (monsterNameIndex < 49) {
                if (monsterNameIndex < 41) {
                    // 33 <= monsterNameIndex <= 40
                    if (monsterNameIndex < 37) {
                        // 33 <= monsterNameIndex <= 36
                        if (monsterNameIndex == 33) {
                            monsterName = "Naga Warrior";
                        } else if (monsterNameIndex == 34) {
                            monsterName = "Lich";
                        } else if (monsterNameIndex == 35) {
                            monsterName = "Bone Dragon";
                        } else {
                            monsterName = "Elemental Guardian";
                        }
                    } else {
                        // 37 <= monsterNameIndex <= 40
                        if (monsterNameIndex == 37) {
                            monsterName = "Wraith Lord";
                        } else if (monsterNameIndex == 38) {
                            monsterName = "Shadow Demon";
                        } else if (monsterNameIndex == 39) {
                            monsterName = "Tainted Night Elf";
                        } else {
                            monsterName = "Nightmare Steed";
                        }
                    }
                } else {
                    // 41 <= monsterNameIndex <= 48
                    if (monsterNameIndex < 45) {
                        // 41 <= monsterNameIndex <= 44
                        if (monsterNameIndex == 41) {
                            monsterName = "Elder Vampire";
                        } else if (monsterNameIndex == 42) {
                            monsterName = "Frost Giant";
                        } else if (monsterNameIndex == 43) {
                            monsterName = "Stone Golem";
                        } else {
                            monsterName = "Iron Golem";
                        }
                    } else {
                        // 45 <= monsterNameIndex <= 48
                        if (monsterNameIndex == 45) {
                            monsterName = "Phoenix";
                        } else if (monsterNameIndex == 46) {
                            monsterName = "Ancient Wyrm";
                        } else if (monsterNameIndex == 47) {
                            monsterName = "Kraken";
                        } else {
                            monsterName = "Behemoth";
                        }
                    }
                }
            } else {
                // 49 <= monsterNameIndex <= 64
                if (monsterNameIndex < 57) {
                    // 49 <= monsterNameIndex <= 56
                    if (monsterNameIndex < 53) {
                        // 49 <= monsterNameIndex <= 52
                        if (monsterNameIndex == 49) {
                            monsterName = "Demon Prince";
                        } else if (monsterNameIndex == 50) {
                            monsterName = "Elder Lich King";
                        } else if (monsterNameIndex == 51) {
                            monsterName = "Shadow Dragon";
                        } else {
                            monsterName = "Eldritch Horror";
                        }
                    } else {
                        // 53 <= monsterNameIndex <= 56
                        if (monsterNameIndex == 53) {
                            monsterName = "Celestial Guardian";
                        } else if (monsterNameIndex == 54) {
                            monsterName = "Fallen Archangel";
                        } else if (monsterNameIndex == 55) {
                            monsterName = "Titan";
                        } else {
                            monsterName = "Leviathan";
                        }
                    }
                } else {
                    // 57 <= monsterNameIndex <= 64
                    if (monsterNameIndex < 61) {
                        // 57 <= monsterNameIndex <= 60
                        if (monsterNameIndex == 57) {
                            monsterName = "World Serpent";
                        } else if (monsterNameIndex == 58) {
                            monsterName = "Void Devourer";
                        } else if (monsterNameIndex == 59) {
                            monsterName = "The Beast";
                        } else {
                            monsterName = "Death's Herald";
                        }
                    } else {
                        // 61 <= monsterNameIndex <= 64
                        if (monsterNameIndex == 61) {
                            monsterName = "Corrupted Ancient One";
                        } else if (monsterNameIndex == 62) {
                            monsterName = "Abyssal Lord";
                        } else if (monsterNameIndex == 63) {
                            monsterName = "Dragon God";
                        } else {
                            monsterName = "Your Mom";
                        }
                    }
                }
            }
        }
        return monsterName;
    }
}
