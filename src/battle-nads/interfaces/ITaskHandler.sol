//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

interface ITaskHandler {
    function processTurn(bytes32 characterID)
        external
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment);
    function processSpawn(bytes32 characterID)
        external
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment);
    function processAbility(bytes32 characterID)
        external
        returns (bool reschedule, uint256 nextBlock, uint256 maxPayment);
    function processAscend(bytes32 characterID) external;
}
