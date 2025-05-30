//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

library Events {
    event CharacterCreated(bytes32 indexed characterID);
    event MonsterCreated(bytes32 indexed characterID);
    event LevelUp(bytes32 indexed areaID, bytes32 indexed characterID, uint256 level);
    event CharacterLeftArea(bytes32 indexed areaID, bytes32 indexed characterID);
    event CharacterEnteredArea(bytes32 indexed areaID, bytes32 indexed characterID);
    event CharactersEnteredCombat(bytes32 indexed areaID, bytes32 indexed attackerID, bytes32 indexed defenderID);
    event CombatMiss(bytes32 indexed areaID, bytes32 indexed attackerID, bytes32 indexed defenderID);
    event CombatHit(
        bytes32 indexed areaID,
        bytes32 indexed attackerID,
        bytes32 indexed defenderID,
        bool isCritical,
        uint256 damage,
        uint256 defenderHealthRemaining
    );
    event CombatHealthRecovered(
        bytes32 indexed areaID, bytes32 indexed characterID, uint256 healthRecovered, uint256 newHealth
    );
    event ChatMessage(bytes32 indexed areaID, bytes32 indexed characterID, string message);
    event LootedNewWeapon(bytes32 indexed areaID, bytes32 indexed characterID, uint8 weaponID, string weaponName);
    event LootedNewArmor(bytes32 indexed areaID, bytes32 indexed characterID, uint8 armorID, string armorName);
    event LootedShMON(bytes32 indexed areaID, bytes32 indexed characterID, uint256 shMonAmount);
    event PlayerDied(bytes32 indexed areaID, bytes32 indexed characterID);
}
