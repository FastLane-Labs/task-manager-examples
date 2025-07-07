//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import {
    BattleNad, BattleArea, StorageTracker, Inventory, BalanceTracker, Log, AbilityTracker, Ability
} from "./Types.sol";

import { Balances } from "./Balances.sol";
import { Errors } from "./libraries/Errors.sol";
import { Events } from "./libraries/Events.sol";
import { Equipment } from "./libraries/Equipment.sol";
import { StatSheet } from "./libraries/StatSheet.sol";

abstract contract Handler is Balances {
    using Equipment for BattleNad;
    using StatSheet for BattleNad;
    using Equipment for Inventory;

    constructor(address taskManager, address shMonad) Balances(taskManager, shMonad) { }

    function handlePlayerCreation(
        address owner,
        string memory name,
        uint256 strength,
        uint256 vitality,
        uint256 dexterity,
        uint256 quickness,
        uint256 sturdiness,
        uint256 luck
    )
        external
        CalledBySelfInTryCatch
        returns (bytes32 characterID)
    {
        BattleNad memory character =
            _buildNewCharacter(owner, name, strength, vitality, dexterity, quickness, sturdiness, luck);
        character.inventory = character.inventory.addWeaponToInventory(character.stats.weaponID);
        character.inventory = character.inventory.addArmorToInventory(character.stats.armorID);
        character = _allocatePlayerBuyIn(character);

        bool scheduled;
        (character, scheduled) = _createOrRescheduleSpawnTask(character, block.number + SPAWN_DELAY);
        if (!scheduled) {
            revert Errors.SpawnTaskNotScheduled();
        }

        _storeBattleNad(character);

        return character.id;
    }

    function _handleSpawn(BattleNad memory player)
        internal
        returns (BattleNad memory, bool reschedule, uint256 blockNumber)
    {
        // Find spawn point
        (BattleArea memory area, uint8 x, uint8 y) = _unrandomSpawnCoordinates(player);
        uint8 depth = 1;
        if (x == 0 && y == 0) {
            return (player, true, block.number + SPAWN_DELAY);
        }

        // Establish a random seed
        bytes32 randomSeed = keccak256(abi.encode(_AREA_SEED, player.id, x, y, depth, blockhash(block.number - 1)));

        // Find an open slot and move to it
        uint8 index = _findNextIndex(area, randomSeed);
        (player, area) = _enterLocation(player, area, x, y, depth, index);

        // Log that we entered the new area
        area = _logEnteredArea(player, area, 0);

        player.tracker.updateStats = true;

        // Store the updated area
        _storeArea(area, player.stats.depth, player.stats.x, player.stats.y);

        // Return
        return (player, false, 0);
    }

    function handleMovement(
        BattleNad memory player,
        uint8 newDepth,
        uint8 newX,
        uint8 newY
    )
        external
        CalledBySelfInTryCatch
        NotWhileDead(player)
        NotWhileInCombat(player)
        returns (BattleNad memory)
    {
        // Validate movement
        _validateLocationChange(player, newDepth, newX, newY);

        // Load the new area
        BattleArea memory area = _loadArea(newDepth, newX, newY);

        // Make sure there's room in the area
        if (uint256(area.playerCount) + uint256(area.monsterCount) >= MAX_COMBATANTS_PER_AREA) {
            revert Errors.AreaFull(newDepth, newX, newY);
        }

        // Store previous depth (only spawn boss monster when trying to go down, not up)
        uint8 prevDepth = player.stats.depth;

        // Establish a random seed
        bytes32 randomSeed =
            keccak256(abi.encode(_AREA_SEED, player.id, newX, newY, newDepth, blockhash(block.number - 1)));

        // Find an open slot and move to it
        _leaveLocation(player);
        (player, area) = _enterLocation(player, area, newX, newY, newDepth, _findNextIndex(area, randomSeed));

        // Return early if it's a no combat zone
        if (_isNoCombatZone(newX, newY, newDepth)) {
            _storeArea(area, player.stats.depth, player.stats.x, player.stats.y);
            return player;
        }

        // Check for aggro
        (uint8 monsterIndex, bool newMonster) = _checkForAggro(player, area, randomSeed, prevDepth);

        // Log that we entered the new area
        area = _logEnteredArea(player, area, monsterIndex);

        // If there's no monster, return early
        if (monsterIndex == 0) {
            _storeArea(area, player.stats.depth, player.stats.x, player.stats.y);
            return player;
        }

        // Load or create the monster
        BattleNad memory monster;

        // CASE: Create monster
        if (newMonster) {
            monster = _buildNewMonster(player);
            (monster, area) = _enterLocation(monster, area, newX, newY, newDepth, monsterIndex);

            // CASE: Load monster
        } else {
            monster = _loadExistingMonster(player, monsterIndex);
        }

        // Flag for combat
        (monster, player) = _enterMutualCombatToTheDeath(monster, player);

        // Create tasks
        bool scheduledTask = false;

        // Only create for monster if task doesn't already exist
        if (newMonster) {
            uint256 targetBlock = block.number + _cooldown(monster.stats) + COMBAT_COLD_START_DELAY_MONSTER;
            (monster, scheduledTask) = _createOrRescheduleCombatTask(monster, targetBlock);
            if (!scheduledTask) {
                emit Events.TaskNotScheduledInHandler(3, monster.id, block.number, targetBlock);
            }
        } else {
            // If task is no longer active, start a new one
            (scheduledTask,) = _checkClearTasks(monster);
            if (!scheduledTask) {
                monster.owner = player.owner;
                monster.tracker.updateOwner = true;
                uint256 targetBlock = block.number + _cooldown(monster.stats) + COMBAT_COLD_START_DELAY_MONSTER;
                (monster, scheduledTask) = _createOrRescheduleCombatTask(monster, targetBlock);
                if (!scheduledTask) {
                    emit Events.TaskNotScheduledInHandler(4, monster.id, block.number, targetBlock);
                }
            }
        }

        if (scheduledTask) {
            uint256 targetBlock = block.number + _cooldown(player.stats) + COMBAT_COLD_START_DELAY_ATTACKER;
            (player, scheduledTask) = _createOrRescheduleCombatTask(player, targetBlock);
            if (!scheduledTask) {
                emit Events.TaskNotScheduledInHandler(5, player.id, block.number, targetBlock);
            }
        }

        // Store area
        _storeArea(area, player.stats.depth, player.stats.x, player.stats.y);

        // Store the monster's data
        _storeBattleNad(monster);

        // Return player
        return player;
    }

    function handleAscend(BattleNad memory player)
        external
        CalledBySelfInTryCatch
        NotWhileDead(player)
        NotWhileInCombat(player)
        OnlyInCombatZones(player)
        returns (BattleNad memory)
    {
        // Commit honorable ascenscion, return inventory balance to owner after delay;
        player = _createOrRescheduleAscendTask(player);

        // Set health to 2 while ascending
        player.stats.health = 2;
        player.tracker.updateStats = true;
        return player;
    }

    function handleAttack(
        BattleNad memory attacker,
        uint256 targetIndex
    )
        external
        CalledBySelfInTryCatch
        NotWhileDead(attacker)
        OnlyInCombatZones(attacker)
        returns (BattleNad memory)
    {
        // Load the target
        BattleNad memory defender =
            _loadCombatant(attacker.stats.depth, attacker.stats.x, attacker.stats.y, targetIndex);

        if (!_isValidID(defender.id)) {
            revert Errors.InvalidTargetIndex(targetIndex);
        }

        // Revert if we can't attack defender because of level cap
        if (!_canEnterMutualCombatToTheDeath(attacker, defender)) {
            revert Errors.CannotAttackDueToLevelCap();
        }

        BattleArea memory area = _loadArea(attacker.stats.depth, attacker.stats.x, attacker.stats.y);

        // Log that we instigated combat
        if (_notYetInCombat(attacker, defender)) {
            area = _logInstigatedCombat(attacker, defender, area);
        }

        if (attacker.stats.nextTargetIndex != uint8(targetIndex)) {
            attacker.stats.nextTargetIndex = uint8(targetIndex);
            attacker.tracker.updateStats = true;
        }

        if (defender.stats.nextTargetIndex == 0) {
            defender.stats.nextTargetIndex = attacker.stats.index;
            defender.tracker.updateStats = true;
        } else if (defender.stats.nextTargetIndex != uint8(attacker.stats.index)) {
            bytes32 defenderTargetID =
                areaCombatants[defender.stats.depth][defender.stats.x][defender.stats.y][defender.stats.nextTargetIndex];
            if (!_isValidID(defenderTargetID)) {
                defender.stats.nextTargetIndex = attacker.stats.index;
                defender.tracker.updateStats = true;
            }
        }

        // Flag for combat
        (attacker, defender) = _enterMutualCombatToTheDeath(attacker, defender);

        // Create tasks
        // Only create for attacker and defendant if tasks don't already exist
        (bool scheduledTask,) = _checkClearTasks(defender);
        if (!scheduledTask) {
            if (defender.isMonster()) {
                defender.owner = attacker.owner;
                defender.tracker.updateOwner = true;
            }
            (defender, scheduledTask) = _createOrRescheduleCombatTask(
                defender, block.number + _cooldown(defender.stats) + COMBAT_COLD_START_DELAY_DEFENDER
            );
            if (!scheduledTask) {
                emit Events.TaskNotScheduledInHandler(
                    1,
                    defender.id,
                    block.number,
                    block.number + _cooldown(defender.stats) + COMBAT_COLD_START_DELAY_DEFENDER
                );
            }
        }

        (scheduledTask,) = _checkClearTasks(attacker);
        if (!scheduledTask) {
            (attacker, scheduledTask) = _createOrRescheduleCombatTask(
                attacker, block.number + _cooldown(attacker.stats) + COMBAT_COLD_START_DELAY_ATTACKER
            );
            // This is being called by a non-task function
            if (!scheduledTask) {
                emit Events.TaskNotScheduledInHandler(
                    2,
                    attacker.id,
                    block.number,
                    block.number + _cooldown(attacker.stats) + COMBAT_COLD_START_DELAY_ATTACKER
                );
            }
        }

        // Store area
        _storeArea(area, attacker.stats.depth, attacker.stats.x, attacker.stats.y);

        // Store the defendant's data
        _storeBattleNad(defender);

        // Return player
        return attacker;
    }

    function handleChat(
        BattleNad memory player,
        string memory message
    )
        external
        CalledBySelfInTryCatch
        NotWhileDead(player)
    {
        if (bytes(message).length > _MAX_CHAT_STRING_LENGTH) {
            revert Errors.InvalidChatMessageLength(bytes(message).length);
        }

        // Emit event with the message
        emit Events.ChatMessage(player.areaID(), player.id, message);

        // Load area
        BattleArea memory area = _loadArea(player);

        // Store the chat log
        area = _storeChatLog(player, area, message);

        // Store area
        _storeArea(area, player);
    }

    function handleChangeWeapon(
        BattleNad memory player,
        uint8 weaponID
    )
        external
        CalledBySelfInTryCatch
        NotWhileDead(player)
        NotWhileInCombat(player)
        returns (BattleNad memory)
    {
        player.inventory = inventories[player.id];

        if (player.inventory.hasWeapon(weaponID)) {
            player.stats.weaponID = weaponID;
            player.tracker.updateStats = true;
        } else {
            revert Errors.WeaponNotInInventory(weaponID);
        }

        // Return player
        return player;
    }

    function handleChangeArmor(
        BattleNad memory player,
        uint8 armorID
    )
        external
        CalledBySelfInTryCatch
        NotWhileDead(player)
        NotWhileInCombat(player)
        returns (BattleNad memory)
    {
        player.inventory = inventories[player.id];

        if (player.inventory.hasArmor(armorID)) {
            player.stats.armorID = armorID;
            player.tracker.updateStats = true;
        } else {
            revert Errors.ArmorNotInInventory(armorID);
        }

        // Return player
        return player;
    }

    function handleAllocatePoints(
        BattleNad memory player,
        uint256 newStrength,
        uint256 newVitality,
        uint256 newDexterity,
        uint256 newQuickness,
        uint256 newSturdiness,
        uint256 newLuck
    )
        external
        CalledBySelfInTryCatch
        NotWhileDead(player)
        NotWhileInCombat(player)
        returns (BattleNad memory)
    {
        uint256 newPoints = newStrength + newVitality + newDexterity + newQuickness + newSturdiness + newLuck;
        uint256 unspentAttributePoints = player.unallocatedStatPoints();

        if (newPoints > unspentAttributePoints) {
            revert Errors.InsufficientStatPoints(unspentAttributePoints, newPoints);
        }

        player.stats.unspentAttributePoints -= uint8(newPoints);

        _updatePlayerLevelInArea(player, newPoints);

        player.stats.strength += uint8(newStrength);
        player.stats.vitality += uint8(newVitality);
        player.stats.dexterity += uint8(newDexterity);
        player.stats.quickness += uint8(newQuickness);
        player.stats.sturdiness += uint8(newSturdiness);
        player.stats.luck += uint8(newLuck);

        player.stats.health = uint16(_maxHealth(player.stats));

        player.tracker.updateStats = true;
        _storeBattleNad(player);
    }

    function _handleCombatTurn(BattleNad memory attacker)
        internal
        returns (BattleNad memory, bool reschedule, uint256 nextExecutionBlock)
    {
        // Load area for log info
        BattleArea memory area = _loadArea(attacker);

        // Verify that attacker is still alive
        if (attacker.isDead()) {
            uint8 depth = attacker.stats.depth;
            uint8 x = attacker.stats.x;
            uint8 y = attacker.stats.y;

            (attacker, area) = _processDeathDuringDeceasedTurn(attacker, area);
            // Store the area
            _storeArea(area, depth, x, y);
            return (attacker, false, 0);
        }

        // Attempt to load a defender, exit if no defenders remain
        BattleNad memory defender;
        (attacker, defender, area) = _getTargetIDAndStats(attacker, area, uint8(0));

        // Start a combat log
        Log memory log = _startCombatLog(attacker, defender);

        if (!_isValidID(defender.id)) {
            (attacker, log) = _regenerateHealth(attacker, log);

            // CASE: No combatants remain
            if (!attacker.isInCombat()) {
                reschedule = false;
                nextExecutionBlock = 0;

                // CASE: Combatant remains, but we must return early
                // NOTE: Might be possible due to running out of gas
            } else {
                reschedule = true;
                nextExecutionBlock = block.number + 1;
            }

            // Store area
            _storeArea(area, attacker.stats.depth, attacker.stats.x, attacker.stats.y);

            // Save and return
            return (attacker, reschedule, nextExecutionBlock);
        }

        // Load equipment
        attacker = attacker.loadEquipment();
        defender = defender.loadEquipment();

        // Process attack
        (attacker, defender, log) = _attack(attacker, defender, log);

        // If it's a monster, update defender's owner to most recent attacker
        // Only do this if there was a funding issue with prev task
        if (defender.isMonster() && !attacker.isMonster()) {
            defender.owner = _loadOwner(defender.id);
            if (defender.owner != attacker.owner) {
                (bool hasActiveCombatTask,) = _checkClearTasks(defender);
                if (!hasActiveCombatTask) {
                    defender.owner = attacker.owner;
                    defender.tracker.updateOwner = true;
                }
            }
        }

        // Check if defender died and handle that case
        if (defender.isDead()) {
            // Process death and potentially get a new defender
            // IMPORTANT: This function already stores the dead defender internally
            BattleNad memory newDefender;
            (attacker, newDefender, area) = _processDeathDuringKillerTurn(attacker, defender, area);

            // Only update defender reference if we got a valid new target
            // This prevents the bug where the wrong player would be stored later
            if (_isValidID(newDefender.id) && newDefender.id != defender.id && newDefender.id != attacker.id) {
                defender = newDefender;
            } else {
                // Set defender to empty so we don't store it again at line 526
                defender.id = bytes32(0);
            }
        }

        // Handle health regen and storage, then return the necessary data
        (attacker, log) = _regenerateHealth(attacker, log);

        // CASE: All opponents have been defeated
        if (!attacker.isInCombat()) {
            attacker = _exitCombat(attacker);
            reschedule = false;
            nextExecutionBlock = 0;

            // CASE: Defenders still exist
        } else {
            reschedule = true;
            nextExecutionBlock = block.number + _cooldown(attacker.stats);
        }

        // Store the log
        area = _storeLog(attacker, area, log);

        // Store area
        _storeArea(area, attacker.stats.depth, attacker.stats.x, attacker.stats.y);

        // Store defender (if valid)
        // Dead defenders were already stored in _processDeathDuringKillerTurn
        if (_isValidID(defender.id)) {
            _storeBattleNad(defender);
        }

        return (attacker, reschedule, nextExecutionBlock);
    }

    // Starts an ability
    function handleAbility(
        BattleNad memory attacker,
        uint256 targetIndex,
        uint256 abilityIndex
    )
        external
        CalledBySelfInTryCatch
        NotWhileDead(attacker)
        OnlyInCombatZones(attacker)
        returns (BattleNad memory)
    {
        // Load ability
        attacker.activeAbility = _loadAbility(attacker.id);

        // Cannot use an ability while on cooldown
        if (_isValidAddress(attacker.activeAbility.taskAddress)) {
            bool reset;
            (attacker, reset) = _checkAbilityTimeout(attacker);
            if (!reset) {
                revert Errors.AbilityStillOnCooldown(attacker.activeAbility.targetBlock);
            }
        }

        // Load the new ability
        attacker.activeAbility.ability = _getAbility(attacker, abilityIndex);
        attacker.activeAbility.targetIndex = uint8(targetIndex);
        attacker.activeAbility.stage = uint8(1);

        bool reschedule;
        uint256 nextBlock;
        (attacker, reschedule, nextBlock) = _handleAbility(attacker);

        // Schedule the task if needed
        if (reschedule) {
            (attacker, reschedule) = _createOrRescheduleAbilityTask(attacker, nextBlock);
            if (!reschedule) {
                revert Errors.TaskNotRescheduled();
            }
        }

        return attacker;
    }

    function _handleAbility(BattleNad memory attacker)
        internal
        returns (BattleNad memory, bool reschedule, uint256 nextBlock)
    {
        // Verify that attacker is still alive
        if (attacker.isDead()) {
            // Process death in combat task
            return (attacker, false, 0);
        }

        // Attempt to load a defender, exit if no defenders remain
        BattleNad memory defender;
        bool loadedDefender = attacker.activeAbility.targetIndex != 0
            && attacker.activeAbility.targetIndex != uint256(attacker.stats.index);
        if (loadedDefender) {
            defender.id = areaCombatants[attacker.stats.depth][attacker.stats.x][attacker.stats.y][attacker
                .activeAbility
                .targetIndex];

            if (!_isValidID(defender.id)) {
                // Return early if target cant be found
                return (attacker, false, 0);
            }
            defender = _loadBattleNad(defender.id, true);

            if (defender.isDead()) {
                // Return early if target cant be found - process their death in regular combat task.
                return (attacker, false, 0);
            }
        }

        // Make sure the characters are in combat if appropriate
        if (_isOffensiveAbility(attacker.activeAbility.ability)) {
            if (!loadedDefender) {
                revert Errors.AbilityMustHaveTarget();
            }

            (bool attackerInCombat, bool defenderInCombat) = _isCurrentlyInCombat(attacker, defender);
            if (!attackerInCombat || !defenderInCombat) {
                (attacker, defender) = _enterMutualCombatToTheDeath(attacker, defender);
            }
        } else {
            if (attacker.activeAbility.targetIndex != 0 && attacker.activeAbility.ability != Ability.Pray) {
                revert Errors.AbilityCantHaveTarget();
            }
        }

        // Do the ability
        (attacker, defender, reschedule, nextBlock) = _processAbility(attacker, defender);

        // Flag for update
        attacker.tracker.updateActiveAbility = true;

        // Store defender
        if (loadedDefender) {
            if (defender.isDead()) {
                // NOTE: Monsters cant use abilities, so attacker cant be a monster, so a null area
                // can be used since no new target is needed.
                BattleArea memory nullArea;
                BattleNad memory newDefender;
                (attacker, newDefender, nullArea) = _processDeathDuringKillerTurn(attacker, defender, nullArea);

                // newDefender should be empty since attacker is not a monster
                // The dead defender was already stored in _processDeathDuringKillerTurn
            } else {
                // Only store if defender is still alive
                _storeBattleNad(defender);
            }
        }

        return (attacker, reschedule, nextBlock);
    }

    function _forceKill(BattleNad memory combatant) internal returns (uint256 cashedOutShMONShares) {
        _leaveLocation(combatant);

        // Remove opponents from being in combat with combatant
        combatant = _combatCheckLoop(combatant, true);

        BalanceTracker memory balanceTracker = balances;

        if (!combatant.isMonster()) {
            --balanceTracker.playerCount;
            balanceTracker.playerSumOfLevels -= uint32(combatant.stats.level);

            uint256 balance = uint256(inventories[combatant.id].balance);
            if (balance > 0) {
                uint256 yieldBoostAmount = balance * YIELD_BOOST_FACTOR / YIELD_BOOST_BASE;
                balance -= yieldBoostAmount;

                _boostYieldShares(yieldBoostAmount);

                cashedOutShMONShares = balance;
            }
        } else {
            --balanceTracker.monsterCount;
            balanceTracker.monsterSumOfLevels -= uint32(combatant.stats.level);
        }

        balances = balanceTracker;

        _deleteBattleNad(combatant);

        // We don't return the battlenad so that we can keep using its location data, but
        // none of the actual data will persist.
        return cashedOutShMONShares;
    }

    function _combatCheckLoop(BattleNad memory combatant, bool forceRemoveCombat) internal returns (BattleNad memory) {
        combatant.tracker.updateStats = true;

        BattleArea memory area = _loadArea(combatant.stats.depth, combatant.stats.x, combatant.stats.y);
        uint256 monsterBitmap = uint256(area.monsterBitMap);
        uint256 combinedBitmap = uint256(area.playerBitMap) | monsterBitmap;

        uint256 combatantBitmap = uint256(combatant.stats.combatantBitMap);
        uint256 combatantBit = 1 << uint256(combatant.stats.index);

        // Flip off this combatant's own bit
        combinedBitmap &= ~combatantBit;
        // Avoid storage load if there's nothing in area bitmap
        if ((combatantBitmap & combinedBitmap) != combatantBitmap) {
            combatantBitmap &= combinedBitmap;
        }

        if (combatantBitmap == 0) {
            return _exitCombat(combatant);
        }

        // Can't have an index of 0, start i at 1.
        uint256 targetIndex = uint256(combatant.stats.nextTargetIndex);
        if (targetIndex == 0) targetIndex = 1;

        while (gasleft() > 215_000 && combatantBitmap != 0) {
            uint256 indexBit = 1 << targetIndex;

            // If in combat, check if opponent exists
            if (combatantBitmap & indexBit != 0) {
                BattleNad memory opponent =
                    _loadCombatant(combatant.stats.depth, combatant.stats.x, combatant.stats.y, targetIndex);
                uint256 opponentBitmap = uint256(opponent.stats.combatantBitMap);

                // CASE: combatant didnt load
                if (!_isValidID(opponent.id)) {
                    combatantBitmap &= ~indexBit;
                    area.monsterBitMap = uint64(uint256(area.monsterBitMap) & ~indexBit);
                    area.playerBitMap = uint64(uint256(area.playerBitMap) & ~indexBit);
                    _clearCombatantArraySlot(
                        combatant.stats.depth, combatant.stats.x, combatant.stats.y, uint8(targetIndex)
                    );
                    area.update = true;

                    // CASE: We're forcibly removing opponent from combat - most likely
                    // because combatant is being forceKilled / despawned
                } else if (forceRemoveCombat) {
                    combatantBitmap &= ~indexBit;
                    opponent.stats.combatantBitMap = uint64(opponentBitmap & ~combatantBit);
                    opponent.tracker.updateStats = true;
                    _storeBattleNad(opponent);

                    // CASE: Opponent is dead
                } else if (opponent.isDead()) {
                    combatantBitmap &= ~indexBit;

                    if (_isDeadUnaware(opponent.id)) {
                        (combatant,, area) = _processDeathDuringKillerTurn(combatant, opponent, area);
                        combatant.tracker.updateStats = true;
                    } else if (_isDeadUnprocessed(opponent.id)) {
                        (opponent, area) = _processDeathDuringDeceasedTurn(opponent, area);
                    } else {
                        area.monsterBitMap = uint64(uint256(area.monsterBitMap) & ~indexBit);
                        area.playerBitMap = uint64(uint256(area.playerBitMap) & ~indexBit);
                        _clearCombatantArraySlot(
                            combatant.stats.depth, combatant.stats.x, combatant.stats.y, uint8(targetIndex)
                        );
                        area.update = true;
                    }

                    // CASE: Opponent isn't in combat with this player
                } else if (opponentBitmap & combatantBit == 0) {
                    // (remove opponent from this char's combat bitmap)
                    combatantBitmap &= ~indexBit;

                    // CASE: Opponent is legitimately in combat with character
                } else {
                    if (opponent.isMonster()) {
                        (bool hasActiveCombatTask,) = _checkClearTasks(opponent);
                        if (!hasActiveCombatTask && !_isTask()) {
                            owners[opponent.id] = _abstractedMsgSender();
                            _restartCombatTask(opponent);
                        }
                    }
                }
            }
            // Increment loop
            unchecked {
                if (++targetIndex > 64) {
                    targetIndex = 1;
                }
            }
            combatant.stats.nextTargetIndex = uint8(targetIndex);
        }

        if (combatantBitmap == 0) {
            combatant = _exitCombat(combatant);
        } else {
            combatant.stats.combatantBitMap = uint64(combatantBitmap);
        }
        _storeArea(area, combatant.stats.depth, combatant.stats.x, combatant.stats.y);
        return combatant;
    }

    modifier CalledBySelfInTryCatch() {
        {
            if (msg.sender != address(this)) {
                revert Errors.InvalidCaller(msg.sender);
            }
        }
        _;
    }

    modifier NotWhileInCombat(BattleNad memory player) {
        {
            if (player.isInCombat()) {
                (bool hasCombatTask, address activeTask) = _checkClearTasks(player);
                player = _combatCheckLoop(player, false);
                if (!hasCombatTask && !_isTask() && player.isInCombat()) {
                    bool restarted;
                    (player, restarted) = _restartCombatTask(player);
                }
                _storeBattleNad(player);
                return;
            }
        }
        _;
    }

    modifier NotWhileDead(BattleNad memory player) {
        {
            if (player.isDead()) {
                revert Errors.CantProcessWhileDead();
            }
        }
        _;
    }

    modifier OnlyInCombatZones(BattleNad memory player) {
        {
            if (_isNoCombatZone(player.stats.x, player.stats.y, player.stats.depth)) {
                revert Errors.CantFightInNoCombatZone(player.stats.x, player.stats.y, player.stats.depth);
            }
        }
        _;
    }
}
