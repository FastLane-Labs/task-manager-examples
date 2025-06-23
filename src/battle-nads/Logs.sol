//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNadStats,
    BattleNad,
    Inventory,
    BalanceTracker,
    LogType,
    Log,
    DataFeed,
    Ability,
    AbilityTracker,
    BattleArea
} from "./Types.sol";

import { Storage } from "./Storage.sol";
import { Errors } from "./libraries/Errors.sol";

abstract contract Logs is Storage {
    bytes4 private constant _LOG_SPACE_SEED = 0x54296eab; // bytes4(keccak256("Log Space ID"));
    bytes4 private constant _CHAT_LOG_SEED = 0x4154879f; // bytes4(keccak256("Chat Log ID"));

    function _logAscend(
        BattleNad memory character,
        BattleArea memory area,
        uint256 cashedOutShMONAmount
    )
        internal
        returns (BattleArea memory)
    {
        // Create a movement log
        Log memory log;
        log.logType = LogType.Ascend;
        log.mainPlayerIndex = character.stats.index;
        log.value = uint128(cashedOutShMONAmount);
        area = _storeLog(character, area, log);
        return area;
    }

    function _logLeftArea(BattleNad memory character) internal {
        // Create a movement log
        Log memory log;
        log.logType = LogType.LeftArea;
        log.mainPlayerIndex = character.stats.index;

        // Load previous area (area in memory is new area)
        BattleArea memory area = _loadArea(character.stats.depth, character.stats.x, character.stats.y);
        area = _storeLog(character, area, log);
        _storeArea(area, character.stats.depth, character.stats.x, character.stats.y);
    }

    function _logEnteredArea(
        BattleNad memory character,
        BattleArea memory area,
        uint8 monsterIndex
    )
        internal
        returns (BattleArea memory)
    {
        // Create a movement log
        Log memory log;
        log.logType = LogType.EnteredArea;
        log.mainPlayerIndex = character.stats.index;
        log.otherPlayerIndex = monsterIndex; // 0 = no monster
        area = _storeLog(character, area, log);
        return area;
    }

    function _logInstigatedCombat(
        BattleNad memory character,
        BattleNad memory target,
        BattleArea memory area
    )
        internal
        returns (BattleArea memory)
    {
        // Create an instigated combat log
        Log memory log;
        log.logType = LogType.InstigatedCombat;
        log.mainPlayerIndex = character.stats.index;
        log.otherPlayerIndex = target.stats.index;
        area = _storeLog(character, area, log);
        return area;
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

        BattleArea memory area = _loadArea(attacker.stats.depth, attacker.stats.x, attacker.stats.y);
        area = _storeLog(attacker, area, log);
        _storeArea(area, attacker.stats.depth, attacker.stats.x, attacker.stats.y);
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
        return _getLogsForBlock(logSpaceID);
    }

    function _getChatLog(bytes32 logSpaceID, uint256 chatLogIndex) internal view returns (string memory) {
        bytes32 chatLogID = _getChatLogID(logSpaceID, chatLogIndex);
        return chatLogs[chatLogID];
    }

    function _getLogsForBlock(bytes32 logSpaceID) internal view returns (Log[] memory thisBlocksLogs) {
        uint256 logCount;
        for (; logCount < 256;) {
            Log memory log = logs[logSpaceID][logCount];
            if (log.mainPlayerIndex == 0) break;
            unchecked {
                ++logCount;
            }
        }

        thisBlocksLogs = new Log[](logCount);
        for (uint256 i; i < logCount; i++) {
            thisBlocksLogs[i] = logs[logSpaceID][i];
        }

        return thisBlocksLogs;
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
        dataFeed.logs = _getLogsForBlock(logSpaceID);

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
        uint256 length = endBlock - startBlock;
        dataFeeds = new DataFeed[](length);
        for (uint256 i; i < length; i++) {
            bytes32 logSpaceID = _getLogSpaceID(character, startBlock + i);
            dataFeeds[i] = _getDataFeedForBlock(logSpaceID, startBlock + i);
        }
        return dataFeeds;
    }

    function _storeLog(
        BattleNad memory character,
        BattleArea memory area,
        Log memory log
    )
        internal
        returns (BattleArea memory)
    {
        bytes32 logSpaceID = _getLogSpaceID(character, block.number);

        uint64 thisBlock64 = uint64(block.number);

        if (thisBlock64 != area.lastLogBlock) {
            area.lastLogBlock = thisBlock64;
            area.lastLogIndex = 0;
        } else {
            if (area.lastLogIndex == type(uint8).max) {
                revert Errors.TooManyLogs();
            }
            ++area.lastLogIndex;
        }
        area.update = true;
        uint256 nextLogIndex = uint256(area.lastLogIndex);

        log.index = uint16(nextLogIndex);
        logs[logSpaceID][nextLogIndex] = log;

        return area;
    }

    function _storeChatLog(
        BattleNad memory character,
        BattleArea memory area,
        string memory chat
    )
        internal
        returns (BattleArea memory)
    {
        bytes32 logSpaceID = _getLogSpaceID(character, block.number);

        uint64 thisBlock64 = uint64(block.number);

        if (thisBlock64 != area.lastLogBlock) {
            area.lastLogBlock = thisBlock64;
            area.lastLogIndex = 0;
        } else {
            if (area.lastLogIndex == type(uint8).max) {
                revert Errors.TooManyLogs();
            }
            ++area.lastLogIndex;
        }
        area.update = true;
        uint256 nextLogIndex = uint256(area.lastLogIndex);

        bytes32 chatLogID = _getChatLogID(logSpaceID, nextLogIndex);

        // Build the log (it will point to the chat entry)
        Log memory log;
        log.logType = LogType.Chat;
        log.mainPlayerIndex = character.stats.index;
        log.index = uint16(nextLogIndex);

        logs[logSpaceID][nextLogIndex] = log;
        chatLogs[chatLogID] = chat;

        return area;
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
