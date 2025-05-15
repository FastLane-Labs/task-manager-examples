//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { Weapon, Armor, BattleNad, BattleNadLite, BattleNadStats, Inventory } from "../Types.sol";

import { Errors } from "./Errors.sol";

library Equipment {
    function loadEquipment(BattleNad memory self) internal pure returns (BattleNad memory) {
        self.weapon = getWeapon(self.stats.weaponID);
        self.armor = getArmor(self.stats.armorID);
        return self;
    }

    function loadEquipment(
        BattleNadLite memory self,
        BattleNadStats memory stats
    )
        internal
        pure
        returns (BattleNadLite memory)
    {
        self.weaponName = stats.weaponID == 0 ? "None" : getWeapon(stats.weaponID).name;
        self.armorName = stats.armorID == 0 ? "None" : getArmor(stats.armorID).name;
        return self;
    }

    function loadWeapon(BattleNad memory self) internal pure returns (BattleNad memory) {
        self.weapon = getWeapon(self.stats.weaponID);
        return self;
    }

    function loadArmor(BattleNad memory self) internal pure returns (BattleNad memory) {
        self.armor = getArmor(self.stats.armorID);
        return self;
    }

    function addWeaponToInventory(Inventory memory self, uint8 weaponID) internal pure returns (Inventory memory) {
        self.weaponBitmap |= uint64(1 << uint256(weaponID));
        return self;
    }

    function addArmorToInventory(Inventory memory self, uint8 armorID) internal pure returns (Inventory memory) {
        self.armorBitmap |= uint64(1 << uint256(armorID));
        return self;
    }

    function hasWeapon(Inventory memory self, uint8 weaponID) internal pure returns (bool) {
        return self.weaponBitmap & uint64(1 << uint256(weaponID)) != 0;
    }

    function hasArmor(Inventory memory self, uint8 armorID) internal pure returns (bool) {
        return self.armorBitmap & uint64(1 << uint256(armorID)) != 0;
    }

    function getWeapon(uint8 weaponID) internal pure returns (Weapon memory weapon) {
        // Hardcoded weapons, query with tree
        if (weaponID < 16) {
            if (weaponID < 8) {
                if (weaponID < 4) {
                    if (weaponID < 2) {
                        if (weaponID == 0) {
                            revert Errors.NoZeroWeapon();
                        } else if (weaponID == 1) {
                            weapon = Weapon({
                                name: "A Dumb-Looking Stick",
                                baseDamage: 105,
                                bonusDamage: 50,
                                accuracy: 85,
                                speed: 100
                            });
                        }
                    } else {
                        if (weaponID == 2) {
                            weapon = Weapon({
                                name: "A Cool-Looking Stick",
                                baseDamage: 110,
                                bonusDamage: 55,
                                accuracy: 80,
                                speed: 100
                            });
                        } else if (weaponID == 3) {
                            weapon = Weapon({
                                name: "Mean Words",
                                baseDamage: 125,
                                bonusDamage: 20,
                                accuracy: 85,
                                speed: 100
                            });
                        }
                    }
                } else {
                    if (weaponID < 6) {
                        if (weaponID == 4) {
                            weapon =
                                Weapon({ name: "A Rock", baseDamage: 145, bonusDamage: 30, accuracy: 75, speed: 100 });
                        } else if (weaponID == 5) {
                            weapon = Weapon({
                                name: "A Club, But It Smells Weird",
                                baseDamage: 120,
                                bonusDamage: 100,
                                accuracy: 80,
                                speed: 100
                            });
                        }
                    } else {
                        if (weaponID == 6) {
                            weapon = Weapon({
                                name: "A Baby Seal",
                                baseDamage: 130,
                                bonusDamage: 75,
                                accuracy: 70,
                                speed: 100
                            });
                        } else if (weaponID == 7) {
                            weapon = Weapon({
                                name: "A Pillow Shaped Like A Sword",
                                baseDamage: 125,
                                bonusDamage: 70,
                                accuracy: 85,
                                speed: 100
                            });
                        }
                    }
                }
            } else {
                if (weaponID < 12) {
                    if (weaponID < 10) {
                        if (weaponID == 8) {
                            weapon = Weapon({
                                name: "Brass Knuckles",
                                baseDamage: 200,
                                bonusDamage: 50,
                                accuracy: 80,
                                speed: 100
                            });
                        } else if (weaponID == 9) {
                            weapon = Weapon({
                                name: "A Pocket Knife",
                                baseDamage: 150,
                                bonusDamage: 150,
                                accuracy: 75,
                                speed: 100
                            });
                        }
                    } else {
                        if (weaponID == 10) {
                            weapon = Weapon({
                                name: "Battle Axe",
                                baseDamage: 250,
                                bonusDamage: 100,
                                accuracy: 70,
                                speed: 85
                            });
                        } else if (weaponID == 11) {
                            weapon = Weapon({
                                name: "A Bowie Knife",
                                baseDamage: 220,
                                bonusDamage: 55,
                                accuracy: 80,
                                speed: 100
                            });
                        }
                    }
                } else {
                    if (weaponID < 14) {
                        if (weaponID == 12) {
                            weapon = Weapon({
                                name: "A Bowstaff",
                                baseDamage: 300,
                                bonusDamage: 10,
                                accuracy: 74,
                                speed: 100
                            });
                        } else if (weaponID == 13) {
                            weapon =
                                Weapon({ name: "A Spear", baseDamage: 200, bonusDamage: 200, accuracy: 70, speed: 100 });
                        }
                    } else {
                        if (weaponID == 14) {
                            weapon = Weapon({
                                name: "A Dagger",
                                baseDamage: 220,
                                bonusDamage: 150,
                                accuracy: 80,
                                speed: 100
                            });
                        } else if (weaponID == 15) {
                            weapon = Weapon({
                                name: "An Actual Sword",
                                baseDamage: 250,
                                bonusDamage: 150,
                                accuracy: 80,
                                speed: 100
                            });
                        }
                    }
                }
            }
        } else if (weaponID < 51) {
            // Extended weapons from 16 to 50
            if (weaponID < 25) {
                if (weaponID < 20) {
                    if (weaponID == 16) {
                        weapon = Weapon({
                            name: "Enchanted Warhammer",
                            baseDamage: 280,
                            bonusDamage: 180,
                            accuracy: 75,
                            speed: 80
                        });
                    } else if (weaponID == 17) {
                        weapon = Weapon({
                            name: "Flaming Longsword",
                            baseDamage: 270,
                            bonusDamage: 200,
                            accuracy: 85,
                            speed: 90
                        });
                    } else if (weaponID == 18) {
                        weapon = Weapon({
                            name: "Frozen Rapier",
                            baseDamage: 250,
                            bonusDamage: 175,
                            accuracy: 90,
                            speed: 105
                        });
                    } else if (weaponID == 19) {
                        weapon =
                            Weapon({ name: "Spiked Mace", baseDamage: 290, bonusDamage: 150, accuracy: 75, speed: 85 });
                    }
                } else {
                    if (weaponID == 20) {
                        weapon = Weapon({
                            name: "Crystal Halberd",
                            baseDamage: 300,
                            bonusDamage: 175,
                            accuracy: 80,
                            speed: 90
                        });
                    } else if (weaponID == 21) {
                        weapon = Weapon({
                            name: "Obsidian Blade",
                            baseDamage: 280,
                            bonusDamage: 220,
                            accuracy: 85,
                            speed: 95
                        });
                    } else if (weaponID == 22) {
                        weapon = Weapon({
                            name: "Thundering Greatsword",
                            baseDamage: 320,
                            bonusDamage: 200,
                            accuracy: 75,
                            speed: 75
                        });
                    } else if (weaponID == 23) {
                        weapon = Weapon({
                            name: "Venomous Whip",
                            baseDamage: 240,
                            bonusDamage: 250,
                            accuracy: 85,
                            speed: 110
                        });
                    } else if (weaponID == 24) {
                        weapon =
                            Weapon({ name: "Shadowblade", baseDamage: 260, bonusDamage: 260, accuracy: 90, speed: 100 });
                    }
                }
            } else if (weaponID < 38) {
                if (weaponID < 30) {
                    if (weaponID == 25) {
                        weapon = Weapon({
                            name: "Double-Bladed Axe",
                            baseDamage: 340,
                            bonusDamage: 170,
                            accuracy: 70,
                            speed: 80
                        });
                    } else if (weaponID == 26) {
                        weapon = Weapon({
                            name: "Ancient War Scythe",
                            baseDamage: 290,
                            bonusDamage: 220,
                            accuracy: 80,
                            speed: 90
                        });
                    } else if (weaponID == 27) {
                        weapon = Weapon({
                            name: "Celestial Quarterstaff",
                            baseDamage: 320,
                            bonusDamage: 200,
                            accuracy: 85,
                            speed: 95
                        });
                    } else if (weaponID == 28) {
                        weapon = Weapon({
                            name: "Soulstealer Katana",
                            baseDamage: 300,
                            bonusDamage: 240,
                            accuracy: 90,
                            speed: 100
                        });
                    } else if (weaponID == 29) {
                        weapon = Weapon({
                            name: "Demonic Trident",
                            baseDamage: 330,
                            bonusDamage: 210,
                            accuracy: 80,
                            speed: 90
                        });
                    }
                } else {
                    if (weaponID == 30) {
                        weapon = Weapon({
                            name: "Volcanic Greataxe",
                            baseDamage: 350,
                            bonusDamage: 200,
                            accuracy: 75,
                            speed: 80
                        });
                    } else if (weaponID == 31) {
                        weapon = Weapon({
                            name: "Ethereal Bow",
                            baseDamage: 280,
                            bonusDamage: 280,
                            accuracy: 95,
                            speed: 100
                        });
                    } else if (weaponID == 32) {
                        weapon = Weapon({
                            name: "Runic Warsword",
                            baseDamage: 320,
                            bonusDamage: 240,
                            accuracy: 85,
                            speed: 90
                        });
                    } else if (weaponID == 33) {
                        weapon =
                            Weapon({ name: "Abyssal Mace", baseDamage: 340, bonusDamage: 230, accuracy: 80, speed: 85 });
                    } else if (weaponID == 34) {
                        weapon = Weapon({
                            name: "Dragon's Tooth Dagger",
                            baseDamage: 300,
                            bonusDamage: 270,
                            accuracy: 90,
                            speed: 105
                        });
                    } else if (weaponID == 35) {
                        weapon = Weapon({
                            name: "Astral Glaive",
                            baseDamage: 330,
                            bonusDamage: 250,
                            accuracy: 85,
                            speed: 90
                        });
                    } else if (weaponID == 36) {
                        weapon = Weapon({
                            name: "Blessed Claymore",
                            baseDamage: 350,
                            bonusDamage: 220,
                            accuracy: 80,
                            speed: 85
                        });
                    } else if (weaponID == 37) {
                        weapon = Weapon({
                            name: "Living Whip Vine",
                            baseDamage: 290,
                            bonusDamage: 290,
                            accuracy: 90,
                            speed: 110
                        });
                    }
                }
            } else {
                if (weaponID < 45) {
                    if (weaponID == 38) {
                        weapon = Weapon({
                            name: "Frostbite Blade",
                            baseDamage: 330,
                            bonusDamage: 260,
                            accuracy: 85,
                            speed: 95
                        });
                    } else if (weaponID == 39) {
                        weapon = Weapon({
                            name: "Spectral Sickle",
                            baseDamage: 310,
                            bonusDamage: 280,
                            accuracy: 90,
                            speed: 100
                        });
                    } else if (weaponID == 40) {
                        weapon = Weapon({
                            name: "Corrupted Cleaver",
                            baseDamage: 360,
                            bonusDamage: 240,
                            accuracy: 80,
                            speed: 85
                        });
                    } else if (weaponID == 41) {
                        weapon = Weapon({
                            name: "Tidal Trident",
                            baseDamage: 340,
                            bonusDamage: 260,
                            accuracy: 85,
                            speed: 90
                        });
                    } else if (weaponID == 42) {
                        weapon = Weapon({
                            name: "Eldritch Staff",
                            baseDamage: 320,
                            bonusDamage: 280,
                            accuracy: 90,
                            speed: 95
                        });
                    } else if (weaponID == 43) {
                        weapon = Weapon({
                            name: "Phoenix Feather Spear",
                            baseDamage: 330,
                            bonusDamage: 270,
                            accuracy: 85,
                            speed: 95
                        });
                    } else if (weaponID == 44) {
                        weapon = Weapon({
                            name: "Starfall Blade",
                            baseDamage: 350,
                            bonusDamage: 260,
                            accuracy: 85,
                            speed: 90
                        });
                    }
                } else {
                    if (weaponID == 45) {
                        weapon =
                            Weapon({ name: "Void Edge", baseDamage: 370, bonusDamage: 250, accuracy: 80, speed: 85 });
                    } else if (weaponID == 46) {
                        weapon = Weapon({
                            name: "Moonlight Greatsword",
                            baseDamage: 340,
                            bonusDamage: 280,
                            accuracy: 85,
                            speed: 90
                        });
                    } else if (weaponID == 47) {
                        weapon = Weapon({
                            name: "Sunforged Hammer",
                            baseDamage: 380,
                            bonusDamage: 240,
                            accuracy: 75,
                            speed: 80
                        });
                    } else if (weaponID == 48) {
                        weapon = Weapon({
                            name: "Nemesis Blade",
                            baseDamage: 360,
                            bonusDamage: 270,
                            accuracy: 85,
                            speed: 90
                        });
                    } else if (weaponID == 49) {
                        weapon = Weapon({
                            name: "Cosmic Crusher",
                            baseDamage: 400,
                            bonusDamage: 230,
                            accuracy: 70,
                            speed: 75
                        });
                    } else if (weaponID == 50) {
                        weapon = Weapon({
                            name: "Ultimate Weapon of Ultimate Destiny",
                            baseDamage: 420,
                            bonusDamage: 300,
                            accuracy: 90,
                            speed: 100
                        });
                    }
                }
            }
        } else {
            revert Errors.WeaponIDNotIncluded(weaponID);
        }
    }

    function getArmor(uint8 armorID) internal pure returns (Armor memory armor) {
        // Hardcoded armors, query with tree
        if (armorID < 16) {
            if (armorID < 8) {
                if (armorID < 4) {
                    if (armorID < 2) {
                        if (armorID == 0) {
                            revert Errors.NoZeroArmor();
                        } else if (armorID == 1) {
                            armor = Armor({
                                name: "Literally Nothing",
                                armorFactor: 0,
                                armorQuality: 0,
                                flexibility: 100,
                                weight: 0
                            });
                        }
                    } else {
                        if (armorID == 2) {
                            armor = Armor({
                                name: "A Scavenged Loin Cloth",
                                armorFactor: 5,
                                armorQuality: 0,
                                flexibility: 100,
                                weight: 0
                            });
                        } else if (armorID == 3) {
                            armor = Armor({
                                name: "A Positive Outlook On Life",
                                armorFactor: 10,
                                armorQuality: 5,
                                flexibility: 100,
                                weight: 0
                            });
                        }
                    }
                } else {
                    if (armorID < 6) {
                        if (armorID == 4) {
                            armor = Armor({
                                name: "Gym Clothes",
                                armorFactor: 15,
                                armorQuality: 5,
                                flexibility: 100,
                                weight: 0
                            });
                        } else if (armorID == 5) {
                            armor = Armor({
                                name: "Tattered Rags",
                                armorFactor: 20,
                                armorQuality: 5,
                                flexibility: 95,
                                weight: 0
                            });
                        }
                    } else {
                        if (armorID == 6) {
                            armor = Armor({
                                name: "98% Mostly-Deceased Baby Seals, 2% Staples",
                                armorFactor: 40,
                                armorQuality: 0,
                                flexibility: 70,
                                weight: 0
                            });
                        } else if (armorID == 7) {
                            armor = Armor({
                                name: "A Padded Jacket",
                                armorFactor: 30,
                                armorQuality: 10,
                                flexibility: 100,
                                weight: 0
                            });
                        }
                    }
                }
            } else {
                if (armorID < 12) {
                    if (armorID < 10) {
                        if (armorID == 8) {
                            armor = Armor({
                                name: "Black Leather Suit (Used)",
                                armorFactor: 40,
                                armorQuality: 10,
                                flexibility: 100,
                                weight: 0
                            });
                        } else if (armorID == 9) {
                            armor = Armor({
                                name: "Tinfoil and Duct Tape",
                                armorFactor: 45,
                                armorQuality: 4,
                                flexibility: 100,
                                weight: 0
                            });
                        }
                    } else {
                        if (armorID == 10) {
                            armor = Armor({
                                name: "Keone's Cod Piece",
                                armorFactor: 30,
                                armorQuality: 75,
                                flexibility: 95,
                                weight: 5
                            });
                        } else if (armorID == 11) {
                            armor = Armor({
                                name: "Chainmail",
                                armorFactor: 55,
                                armorQuality: 15,
                                flexibility: 90,
                                weight: 10
                            });
                        }
                    }
                } else {
                    if (armorID < 14) {
                        if (armorID == 12) {
                            armor = Armor({
                                name: "Scalemail",
                                armorFactor: 60,
                                armorQuality: 18,
                                flexibility: 88,
                                weight: 15
                            });
                        } else if (armorID == 13) {
                            armor = Armor({
                                name: "Kevlar",
                                armorFactor: 60,
                                armorQuality: 20,
                                flexibility: 100,
                                weight: 5
                            });
                        }
                    } else {
                        if (armorID == 14) {
                            armor = Armor({
                                name: "Kevlar + Tactical",
                                armorFactor: 60,
                                armorQuality: 18,
                                flexibility: 100,
                                weight: 5
                            });
                        } else if (armorID == 15) {
                            armor = Armor({
                                name: "Ninja Gear",
                                armorFactor: 10,
                                armorQuality: 100,
                                flexibility: 110,
                                weight: 0
                            });
                        }
                    }
                }
            }
        } else if (armorID < 51) {
            // Extended armors from 16 to 50
            if (armorID < 25) {
                if (armorID < 20) {
                    if (armorID == 16) {
                        armor = Armor({
                            name: "Dragonhide Leather",
                            armorFactor: 65,
                            armorQuality: 25,
                            flexibility: 95,
                            weight: 5
                        });
                    } else if (armorID == 17) {
                        armor = Armor({
                            name: "Reinforced Platemail",
                            armorFactor: 75,
                            armorQuality: 20,
                            flexibility: 70,
                            weight: 25
                        });
                    } else if (armorID == 18) {
                        armor = Armor({
                            name: "Elven Silverweave",
                            armorFactor: 60,
                            armorQuality: 30,
                            flexibility: 100,
                            weight: 3
                        });
                    } else if (armorID == 19) {
                        armor = Armor({
                            name: "Dwarven Full Plate",
                            armorFactor: 80,
                            armorQuality: 25,
                            flexibility: 65,
                            weight: 30
                        });
                    }
                } else {
                    if (armorID == 20) {
                        armor = Armor({
                            name: "Enchanted Robes",
                            armorFactor: 50,
                            armorQuality: 40,
                            flexibility: 105,
                            weight: 2
                        });
                    } else if (armorID == 21) {
                        armor = Armor({
                            name: "Crystal-Infused Mail",
                            armorFactor: 70,
                            armorQuality: 35,
                            flexibility: 85,
                            weight: 15
                        });
                    } else if (armorID == 22) {
                        armor = Armor({
                            name: "Beastmancer Hide",
                            armorFactor: 65,
                            armorQuality: 35,
                            flexibility: 90,
                            weight: 8
                        });
                    } else if (armorID == 23) {
                        armor = Armor({
                            name: "Shadow Cloak",
                            armorFactor: 55,
                            armorQuality: 45,
                            flexibility: 110,
                            weight: 1
                        });
                    } else if (armorID == 24) {
                        armor = Armor({
                            name: "Volcanic Forged Armor",
                            armorFactor: 85,
                            armorQuality: 30,
                            flexibility: 70,
                            weight: 25
                        });
                    }
                }
            } else if (armorID < 38) {
                if (armorID < 30) {
                    if (armorID == 25) {
                        armor = Armor({
                            name: "Celestial Breastplate",
                            armorFactor: 75,
                            armorQuality: 40,
                            flexibility: 80,
                            weight: 20
                        });
                    } else if (armorID == 26) {
                        armor = Armor({
                            name: "Abyssal Shroud",
                            armorFactor: 60,
                            armorQuality: 50,
                            flexibility: 95,
                            weight: 5
                        });
                    } else if (armorID == 27) {
                        armor = Armor({
                            name: "Guardian's Platemail",
                            armorFactor: 90,
                            armorQuality: 35,
                            flexibility: 65,
                            weight: 30
                        });
                    } else if (armorID == 28) {
                        armor = Armor({
                            name: "Sylvan Leaf Armor",
                            armorFactor: 65,
                            armorQuality: 45,
                            flexibility: 100,
                            weight: 3
                        });
                    } else if (armorID == 29) {
                        armor = Armor({
                            name: "Runic Warden Plate",
                            armorFactor: 80,
                            armorQuality: 40,
                            flexibility: 75,
                            weight: 25
                        });
                    }
                } else {
                    if (armorID == 30) {
                        armor = Armor({
                            name: "Spectral Shroud",
                            armorFactor: 70,
                            armorQuality: 50,
                            flexibility: 95,
                            weight: 0
                        });
                    } else if (armorID == 31) {
                        armor = Armor({
                            name: "Void-Touched Mail",
                            armorFactor: 85,
                            armorQuality: 45,
                            flexibility: 80,
                            weight: 15
                        });
                    } else if (armorID == 32) {
                        armor = Armor({
                            name: "Bloodforged Plate",
                            armorFactor: 95,
                            armorQuality: 40,
                            flexibility: 65,
                            weight: 30
                        });
                    } else if (armorID == 33) {
                        armor = Armor({
                            name: "Astral Silk Robes",
                            armorFactor: 60,
                            armorQuality: 55,
                            flexibility: 110,
                            weight: 2
                        });
                    } else if (armorID == 34) {
                        armor = Armor({
                            name: "Stormcaller Armor",
                            armorFactor: 80,
                            armorQuality: 50,
                            flexibility: 85,
                            weight: 20
                        });
                    } else if (armorID == 35) {
                        armor = Armor({
                            name: "Frostweave Garment",
                            armorFactor: 75,
                            armorQuality: 55,
                            flexibility: 90,
                            weight: 10
                        });
                    } else if (armorID == 36) {
                        armor = Armor({
                            name: "Infernal Scale Armor",
                            armorFactor: 90,
                            armorQuality: 45,
                            flexibility: 75,
                            weight: 25
                        });
                    } else if (armorID == 37) {
                        armor = Armor({
                            name: "Divine Protector Suit",
                            armorFactor: 85,
                            armorQuality: 55,
                            flexibility: 80,
                            weight: 20
                        });
                    }
                }
            } else {
                if (armorID < 45) {
                    if (armorID == 38) {
                        armor = Armor({
                            name: "Ethereal Weave",
                            armorFactor: 70,
                            armorQuality: 60,
                            flexibility: 105,
                            weight: 0
                        });
                    } else if (armorID == 39) {
                        armor = Armor({
                            name: "Obsidian Battle Plate",
                            armorFactor: 100,
                            armorQuality: 50,
                            flexibility: 60,
                            weight: 35
                        });
                    } else if (armorID == 40) {
                        armor = Armor({
                            name: "Phoenix Feather Cloak",
                            armorFactor: 75,
                            armorQuality: 60,
                            flexibility: 100,
                            weight: 5
                        });
                    } else if (armorID == 41) {
                        armor = Armor({
                            name: "Dragon Knight Armor",
                            armorFactor: 95,
                            armorQuality: 55,
                            flexibility: 70,
                            weight: 30
                        });
                    } else if (armorID == 42) {
                        armor = Armor({
                            name: "Soul-Bonded Plate",
                            armorFactor: 85,
                            armorQuality: 60,
                            flexibility: 85,
                            weight: 20
                        });
                    } else if (armorID == 43) {
                        armor = Armor({
                            name: "Living Mushroom Armor",
                            armorFactor: 80,
                            armorQuality: 65,
                            flexibility: 90,
                            weight: 15
                        });
                    } else if (armorID == 44) {
                        armor = Armor({
                            name: "Cosmic Veil",
                            armorFactor: 75,
                            armorQuality: 70,
                            flexibility: 100,
                            weight: 5
                        });
                    }
                } else {
                    if (armorID == 45) {
                        armor = Armor({
                            name: "Titan's Bulwark",
                            armorFactor: 105,
                            armorQuality: 60,
                            flexibility: 60,
                            weight: 40
                        });
                    } else if (armorID == 46) {
                        armor = Armor({
                            name: "Moonlight Shroud",
                            armorFactor: 80,
                            armorQuality: 70,
                            flexibility: 95,
                            weight: 10
                        });
                    } else if (armorID == 47) {
                        armor = Armor({
                            name: "Sunforged Plate",
                            armorFactor: 100,
                            armorQuality: 65,
                            flexibility: 70,
                            weight: 30
                        });
                    } else if (armorID == 48) {
                        armor = Armor({
                            name: "Chronoshifter's Garb",
                            armorFactor: 90,
                            armorQuality: 75,
                            flexibility: 85,
                            weight: 15
                        });
                    } else if (armorID == 49) {
                        armor = Armor({
                            name: "Crystalline Exoskeleton",
                            armorFactor: 95,
                            armorQuality: 70,
                            flexibility: 80,
                            weight: 25
                        });
                    } else if (armorID == 50) {
                        armor = Armor({
                            name: "Ultimate Armor of Ultimate Protection",
                            armorFactor: 110,
                            armorQuality: 80,
                            flexibility: 90,
                            weight: 20
                        });
                    }
                }
            }
        } else {
            revert Errors.ArmorIDNotIncluded(armorID);
        }
    }
}
