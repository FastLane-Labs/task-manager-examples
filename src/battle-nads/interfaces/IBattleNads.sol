//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNad,
    BattleNadLite,
    BattleNadStats,
    Inventory,
    Weapon,
    Armor,
    StorageTracker,
    StatusEffect,
    CharacterClass,
    Ability,
    AbilityTracker,
    DataFeed,
    Log,
    LogType
} from "../Types.sol";
import { SessionKeyData } from "../cashier/CashierTypes.sol";

interface IBattleNads {
    // Cashier interface
    function getCurrentSessionKeyData(address owner) external view returns (SessionKeyData memory sessionKeyData);
    function updateSessionKey(address sessionKeyAddress, uint256 expiration) external payable;
    function replenishGasBalance() external payable;
    function deactivateSessionKey(address sessionKeyAddress) external payable;

    // Getters
    function pollForFrontendData(
        address owner,
        uint256 startBlock
    )
        external
        view
        returns (
            bytes32 characterID,
            SessionKeyData memory sessionKeyData,
            BattleNad memory character,
            BattleNadLite[] memory combatants,
            BattleNadLite[] memory noncombatants,
            uint8[] memory equipableWeaponIDs,
            string[] memory equipableWeaponNames,
            uint8[] memory equipableArmorIDs,
            string[] memory equipableArmorNames,
            DataFeed[] memory dataFeeds,
            uint256 balanceShortfall,
            uint256 unallocatedAttributePoints,
            uint256 endBlock
        );

    function getDataFeed(
        address owner,
        uint256 startBlock,
        uint256 endBlock
    )
        external
        view
        returns (DataFeed[] memory dataFeeds);

    function getPlayerCharacterID(address owner) external view returns (bytes32 characterID);
    function getBattleNad(bytes32 characterID) external view returns (BattleNad memory character);
    function getBattleNadLite(bytes32 characterID) external view returns (BattleNadLite memory character);
    function shortfallToRecommendedBalanceInMON(bytes32 characterID) external view returns (uint256 minAmount);
    function estimateBuyInAmountInMON() external view returns (uint256 minAmount);
    function getWeaponName(uint8 weaponID) external view returns (string memory);
    function getArmorName(uint8 armorID) external pure returns (string memory);

    // Entrypoint Functions
    function moveNorth(bytes32 characterID) external;
    function moveSouth(bytes32 characterID) external;
    function moveEast(bytes32 characterID) external;
    function moveWest(bytes32 characterID) external;
    function moveUp(bytes32 characterID) external;
    function moveDown(bytes32 characterID) external;
    function attack(bytes32 characterID, uint256 targetIndex) external;

    function useAbility(bytes32 characterID, uint256 targetIndex, uint256 abilityIndex) external;
    function ascend(bytes32 characterID) external payable;
    function equipWeapon(bytes32 characterID, uint8 weaponID) external;
    function equipArmor(bytes32 characterID, uint8 armorID) external;

    function createCharacter(
        string memory name,
        uint256 strength,
        uint256 vitality,
        uint256 dexterity,
        uint256 quickness,
        uint256 sturdiness,
        uint256 luck,
        address sessionKey,
        uint256 sessionKeyDeadline
    )
        external
        payable
        returns (bytes32 characterID);

    function allocatePoints(
        bytes32 characterID,
        uint256 newStrength,
        uint256 newVitality,
        uint256 newDexterity,
        uint256 newQuickness,
        uint256 newSturdiness,
        uint256 newLuck
    )
        external;

    function zoneChat(bytes32 characterID, string calldata message) external;
}
