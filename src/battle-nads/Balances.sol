//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import { BattleNad, BattleNadStats, Inventory, BalanceTracker, Log } from "./Types.sol";

import { GasRelayWithScheduling } from "lib/fastlane-contracts/src/common/relay/GasRelayWithScheduling.sol";
import { Errors } from "./libraries/Errors.sol";
import { Events } from "./libraries/Events.sol";
import { StatSheet } from "./libraries/StatSheet.sol";
import { IShMonad } from "@fastlane-contracts/shmonad/interfaces/IShMonad.sol";

import { Instances } from "./Instances.sol";

// These are the entrypoint functions called by the tasks
abstract contract Balances is GasRelayWithScheduling, Instances {
    using StatSheet for BattleNad;
    using StatSheet for BattleNadStats;

    constructor(
        address taskManager,
        address shMonad
    )
        GasRelayWithScheduling(
            MIN_EXECUTION_GAS + MOVEMENT_EXTRA_GAS + BASE_TX_GAS_COST + MIN_REMAINDER_GAS_BUFFER,
            8,
            4,
            50_000,
            50_000
        )
    { }

    function _allocatePlayerBuyIn(BattleNad memory character) internal returns (BattleNad memory) {
        // Load the owner's balance
        uint256 ownerShares = _sharesBondedToThis(character.owner);
        uint256 buyInShares = _convertMonToWithdrawnShMon(BUY_IN_AMOUNT);

        // Validate balances
        if (ownerShares < buyInShares) {
            revert Errors.BondedBalanceTooLow(ownerShares, buyInShares);
        }

        // Pull the buy-in
        _takeFromOwnerBondedShares(character.owner, buyInShares);

        // Allocate a portion of it to the player
        uint256 playerPortion = buyInShares * PLAYER_ALLOCATION / BALANCE_BASE;
        uint256 monsterPortion = buyInShares - playerPortion; // - 1;
        // _bondSharesToTaskManager(1); // prevent null value cold storage write

        // Load the monster balances
        BalanceTracker memory balanceTracker = balances;

        // Increment the counts and monster balance
        ++balanceTracker.playerCount;
        ++balanceTracker.playerSumOfLevels; // everyone starts at level one
        balanceTracker.monsterSumOfBalances += uint128(monsterPortion);

        // Store the BalanceTracker
        balances = balanceTracker;

        // Increment the player's balance in their own inventory
        character.inventory.balance += uint128(playerPortion);
        character.tracker.updateInventory = true;
        return character;
    }

    function _allocateBalanceInDeath(
        BattleNad memory victor,
        BattleNad memory defeated,
        Log memory log
    )
        internal
        override
        returns (BattleNad memory, BattleNad memory, Log memory)
    {
        // Load the balances
        BalanceTracker memory balanceTracker = balances;
        uint256 defeatedBalance;

        // Decrement losing side
        // CASE: Defeated is a monster
        if (defeated.isMonster()) {
            // Calculate and adjust balance
            defeatedBalance = uint256(balanceTracker.monsterSumOfBalances) * uint256(defeated.stats.level)
                / uint256(balanceTracker.monsterSumOfLevels);
            defeatedBalance /= ((balanceTracker.playerCount + balanceTracker.monsterCount + 1) * 16);
            if (defeatedBalance > 0) --defeatedBalance;
            balanceTracker.monsterSumOfBalances -= uint128(defeatedBalance);

            // Handle decrements
            --balanceTracker.monsterCount;
            balanceTracker.monsterSumOfLevels -= uint32(defeated.stats.level);

            // CASE: Defeated is a player
        } else {
            // Calculate and adjust balance
            defeatedBalance = uint256(defeated.inventory.balance);
            defeated.inventory.balance = uint128(0);

            // Handle decrements
            balanceTracker.playerSumOfLevels -= uint32(defeated.stats.level);
            --balanceTracker.playerCount;

            // Flag for inventory update
            if (!defeated.tracker.updateInventory) defeated.tracker.updateInventory = true;
        }

        // Boost shmonad yield with a portion of the defeated balance
        uint256 boostYieldPortion = defeatedBalance * YIELD_BOOST_FACTOR / YIELD_BOOST_BASE;
        defeatedBalance -= boostYieldPortion;

        // Add to payouts
        _boostYieldShares(boostYieldPortion);

        // If the victor is a monster
        if (victor.isMonster()) {
            balanceTracker.monsterSumOfBalances += uint128(defeatedBalance);
            log.value = uint128(defeatedBalance);
            // If the victor is a player
        } else {
            // If victor is higher level than defeated, give a portion to monsters
            if (victor.stats.level > defeated.stats.level) {
                uint256 levelDifference = uint256(victor.stats.level) - uint256(defeated.stats.level);
                uint256 victorPortion = defeatedBalance * uint256(victor.stats.level)
                    / (uint256(victor.stats.level) + (2 * levelDifference));
                uint256 monsterPortion = defeatedBalance - victorPortion;
                balanceTracker.monsterSumOfBalances += uint128(monsterPortion);
                defeatedBalance = victorPortion;
            }

            log.value = uint128(defeatedBalance);

            // Increment the victor's balance
            victor.inventory.balance += uint128(defeatedBalance);
            if (!victor.tracker.updateInventory) victor.tracker.updateInventory = true;

            // Emit event
            emit Events.LootedShMON(victor.areaID(), victor.id, defeatedBalance);
        }

        // Store the BalanceTracker
        balances = balanceTracker;

        return (victor, defeated, log);
    }

    function _allocateOverchargeToMonsters(uint256 shares) internal {
        if (shares == 0) return;

        BalanceTracker memory balanceTracker = balances;

        // Add the portion
        balanceTracker.monsterSumOfBalances += uint128(shares);

        // Store the BalanceTracker
        balances = balanceTracker;
    }

    function _getMinTaskReserveAmount() internal view returns (uint256 minBondedAmount) {
        minBondedAmount = TASK_COMMIT_RESERVE_FACTOR * _estimateTaskCost(block.number + SPAWN_DELAY, TASK_GAS);
    }

    function _getMinTaskReserveShares() internal view returns (uint256 minBondedShares) {
        minBondedShares = _convertMonToWithdrawnShMon(_getMinTaskReserveAmount());
    }

    function _getBuyInAmountInMON() internal view returns (uint256 minAmount) {
        minAmount = BUY_IN_AMOUNT + MIN_BONDED_AMOUNT + _getMinTaskReserveAmount();
    }

    function _getBuyInAmountInShMON() internal view returns (uint256 minBondedShares) {
        minBondedShares = _convertDepositedMonToShMon(_getBuyInAmountInMON());
    }

    function _getRecommendedBalanceInMON() internal view returns (uint256 minAmount) {
        minAmount = MIN_BONDED_AMOUNT + _getMinTaskReserveAmount();
    }

    function _getRecommendedBalanceInShMON() internal view returns (uint256 minBondedShares) {
        minBondedShares = _convertMonToWithdrawnShMon(_getRecommendedBalanceInMON());
    }

    // If a player's bonded balance drops below this amount and they can't reschedule a task then
    // they are removed from combat and at risk of deletion
    function _deletionFloorShares() internal view returns (uint256 minShares) {
        minShares = _convertMonToWithdrawnShMon(_estimateTaskCost(block.number + SPAWN_DELAY, TASK_GAS)) * 2;
    }

    // Override the _minBondedShares value in GasRelayBase.sol so that the session key doesn't
    // take shMON that is committed to be used by the task manager for combat automation
    function _minBondedShares(address account) internal view override returns (uint256 shares) {
        // if (account == tx.origin) {
        //    return _getBuyInAmountInShMON();
        // }
        return _getMinTaskReserveShares();
    }

    // Overrides the max payment function to allow for top up values
    function _maxPayment(address owner) internal override returns (uint256) {
        return _amountBondedToThis(owner) + IShMonad(SHMONAD).topUpAvailable(POLICY_ID(), owner, true);
    }
}
