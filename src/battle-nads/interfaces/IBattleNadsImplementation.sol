//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

interface IBattleNadsImplementation {
    function execute(bytes32 characterID) external;
    function spawn(bytes32 characterID) external;
    function ability(bytes32 characterID) external;
    function ascend(bytes32 characterID) external;
}
