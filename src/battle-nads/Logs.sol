//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNadStats,
    BattleNad,
    BattleInstance,
    Inventory,
    BalanceTracker,
    BattleArea,
    LogType,
    Log,
    DataFeed,
    Ability,
    AbilityTracker
} from "./Types.sol";

import { Storage } from "./Storage.sol";
import { Errors } from "./libraries/Errors.sol";

abstract contract Logs is Storage {
    bytes4 private constant _LOG_SPACE_SEED = 0x54296eab; // bytes4(keccak256("Log Space ID"));
    bytes4 private constant _CHAT_LOG_SEED = 0x4154879f; // bytes4(keccak256("Chat Log ID"));

    function _logAscend(BattleNad memory character, uint256 cashedOutShMONAmount) internal {
        // Create a movement log
        Log memory log;
        log.logType = LogType.Ascend;
        log.mainPlayerIndex = character.stats.index;
        log.value = uint128(cashedOutShMONAmount);
        _storeLog(character, log);
    }

    function _logLeftArea(BattleNad memory character) internal {
        // Create a movement log
        Log memory log;
        log.logType = LogType.LeftArea;
        log.mainPlayerIndex = character.stats.index;
        _storeLog(character, log);
    }

    function _logEnteredArea(BattleNad memory character, uint8 monsterIndex) internal {
        // Create a movement log
        Log memory log;
        log.logType = LogType.EnteredArea;
        log.mainPlayerIndex = character.stats.index;
        log.otherPlayerIndex = monsterIndex; // 0 = no monster
        _storeLog(character, log);
    }

    function _logInstigatedCombat(BattleNad memory character, BattleNad memory target) internal {
        // Create an instigated combat log
        Log memory log;
        log.logType = LogType.InstigatedCombat;
        log.mainPlayerIndex = character.stats.index;
        log.otherPlayerIndex = target.stats.index;
        _storeLog(character, log);
    }

    function _logAbility(
        BattleNad memory attacker,
        BattleNad memory defender,
        Ability ability,
        uint8 stage,
        uint256 damage,
        uint256 healed,
        uint256 nextBlock
    )
        internal
    {
        Log memory log;
        log.logType = LogType.Ability;
        log.mainPlayerIndex = attacker.stats.index;
        log.otherPlayerIndex = defender.stats.index;
        log.damageDone = uint16(damage);
        log.healthHealed = uint16(healed);
        log.lootedWeaponID = uint8(ability);
        log.lootedArmorID = uint8(stage);
        log.value = uint128(nextBlock);
        _storeLog(attacker, log);
    }

    function _startCombatLog(
        BattleNad memory attacker,
        BattleNad memory defender
    )
        internal
        pure
        returns (Log memory log)
    {
        // Create an instigated combat log
        log.logType = LogType.Combat;
        log.mainPlayerIndex = attacker.stats.index;
        log.otherPlayerIndex = defender.stats.index;
        return log;
    }

    function _getLogsForBlock(BattleNad memory character, uint256 blockNumber) internal view returns (Log[] memory) {
        bytes32 logSpaceID = _getLogSpaceID(character, blockNumber);
        return logs[logSpaceID];
    }

    function _getChatLog(bytes32 logSpaceID, uint256 chatLogIndex) internal view returns (string memory) {
        bytes32 chatLogID = _getChatLogID(logSpaceID, chatLogIndex);
        return chatLogs[chatLogID];
    }

    function _getDataFeedForBlock(
        bytes32 logSpaceID,
        uint256 blockNumber
    )
        internal
        view
        returns (DataFeed memory dataFeed)
    {
        dataFeed.blockNumber = blockNumber;
        dataFeed.logs = logs[logSpaceID];

        uint256 chatLogCount = 0;
        for (uint256 i = 0; i < dataFeed.logs.length; i++) {
            if (dataFeed.logs[i].logType == LogType.Chat) {
                chatLogCount++;
            }
        }

        dataFeed.chatLogs = new string[](chatLogCount);

        uint256 chatLogIndex = 0;
        for (uint256 i = 0; i < dataFeed.logs.length; i++) {
            Log memory log = dataFeed.logs[i];
            if (log.logType == LogType.Chat) {
                dataFeed.chatLogs[chatLogIndex] = _getChatLog(logSpaceID, log.index);
                chatLogIndex++;
            }
        }

        return dataFeed;
    }

    function _getDataFeedForRange(
        BattleNad memory character,
        uint256 startBlock,
        uint256 endBlock
    )
        internal
        view
        returns (DataFeed[] memory dataFeeds)
    {
        uint256 length = 1 + endBlock - startBlock;
        dataFeeds = new DataFeed[](length);
        for (uint256 i; i < length; i++) {
            bytes32 logSpaceID = _getLogSpaceID(character, startBlock + i);
            dataFeeds[i] = _getDataFeedForBlock(logSpaceID, startBlock + i);
        }
        return dataFeeds;
    }

    function _storeLog(BattleNad memory character, Log memory log) internal {
        bytes32 logSpaceID = _getLogSpaceID(character, block.number);

        uint256 nextLogIndex = logs[logSpaceID].length;

        if (nextLogIndex >= type(uint16).max) {
            revert Errors.TooManyLogs();
        }

        log.index = uint16(nextLogIndex);

        logs[logSpaceID].push(log);
    }

    function _storeChatLog(BattleNad memory character, string memory chat) internal {
        bytes32 logSpaceID = _getLogSpaceID(character, block.number);
        uint256 nextLogIndex = logs[logSpaceID].length;
        bytes32 chatLogID = _getChatLogID(logSpaceID, nextLogIndex);

        if (nextLogIndex >= type(uint16).max) {
            revert Errors.TooManyLogs();
        }

        // Build the log (it will point to the chat entry)
        Log memory log;
        log.logType = LogType.Chat;
        log.mainPlayerIndex = character.stats.index;
        log.index = uint16(nextLogIndex);

        logs[logSpaceID].push(log);
        chatLogs[chatLogID] = chat;
    }

    function _getLogSpaceID(
        BattleNad memory character,
        uint256 blockNumber
    )
        internal
        pure
        returns (bytes32 logSpaceID)
    {
        logSpaceID = keccak256(
            abi.encodePacked(_LOG_SPACE_SEED, character.stats.depth, character.stats.x, character.stats.y, blockNumber)
        );
    }

    function _getChatLogID(bytes32 logSpaceID, uint256 chatLogIndex) internal pure returns (bytes32 chatLogID) {
        chatLogID = keccak256(abi.encodePacked(_CHAT_LOG_SEED, logSpaceID, chatLogIndex));
    }
}
