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
    PayoutTracker
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
        returns (BattleNad memory character)
    {
        character = _buildNewCharacter(owner, name, strength, vitality, dexterity, quickness, sturdiness, luck);
        character.inventory = character.inventory.addWeaponToInventory(character.stats.weaponID);
        character.inventory = character.inventory.addArmorToInventory(character.stats.armorID);
        character = _allocatePlayerBuyIn(character);

        bool scheduled;
        (character, scheduled) = _createSpawnTask(character, block.number + SPAWN_DELAY);
        if (!scheduled) {
            revert Errors.SpawnTaskNotScheduled();
        }

        return character;
    }

    function _handleSpawn(BattleNad memory player)
        internal
        returns (BattleNad memory, bool reschedule, uint256 blockNumber)
    {
        // Find spawn point
        (BattleArea memory area, uint8 x, uint8 y) = _randomSpawnCoordinates(player);
        uint8 depth = 1;
        if (x == 0 && y == 0) {
            return (player, true, block.number + 8);
        }

        // Establish a random seed
        bytes32 randomSeed = keccak256(abi.encode(_AREA_SEED, player.id, x, y, depth, blockhash(block.number - 1)));

        // Find an open slot and move to it
        uint8 index = _findNextIndex(area, randomSeed);
        (player, area) = _enterLocation(player, area, x, y, depth, index);

        // Log that we entered the new area
        _logEnteredArea(player, 0);

        player.tracker.updateStats = true;

        // Store the updated area
        _storeArea(area);

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

        // Log that we left the previous area
        _logLeftArea(player);

        // Establish a random seed
        bytes32 randomSeed =
            keccak256(abi.encode(_AREA_SEED, player.id, newX, newY, newDepth, blockhash(block.number - 1)));

        // Find an open slot and move to it
        uint8 newIndex = _findNextIndex(area, randomSeed);
        (player, area) = _enterLocation(player, area, newX, newY, newDepth, newIndex);

        // Check for aggro
        (uint8 monsterIndex, bool newMonster) = _checkForAggro(player, area, randomSeed, prevDepth);

        // Log that we entered the new area
        _logEnteredArea(player, monsterIndex);

        // If there's no monster, return early
        if (monsterIndex == 0) {
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
        bool scheduledTask = true; // Set as true to assume there's no monster task

        // Only create for monster if task doesn't already exist
        if (newMonster) {
            uint256 targetBlock = block.number + _cooldown(monster.stats);
            (monster, scheduledTask) = _createCombatTask(monster, targetBlock);
        } else {
            // If task is no longer active, start a new one
            if (characterTasks[monster.id] == address(0)) {
                uint256 targetBlock = block.number + _cooldown(monster.stats);
                (monster, scheduledTask) = _createCombatTask(monster, targetBlock);
            }
        }

        if (scheduledTask) {
            uint256 targetBlock = block.number + _cooldown(player.stats);
            (player, scheduledTask) = _createCombatTask(player, targetBlock);
        }

        // This is being called by a non-task function, so revert if we failed to schedule the task
        if (!scheduledTask) {
            revert Errors.TaskNotScheduled();
        }

        // Store area
        _storeArea(area);

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
        returns (BattleNad memory)
    {
        // Commit honorable ascenscion, return inventory balance to owner after delay;
        player = _createAscendTask(player);

        // Set health to 1 while ascending
        player.stats.health = 1;
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
        returns (BattleNad memory)
    {
        // Load the area
        BattleArea memory area = _loadArea(attacker.stats.depth, attacker.stats.x, attacker.stats.y);
        if (!_isValidTarget(area, targetIndex)) {
            revert Errors.InvalidTargetIndex(targetIndex);
        }

        // Load the target
        BattleNad memory defender = _loadCombatant(area, targetIndex);

        // Revert if we can't attack defender because of level cap
        if (!_canEnterMutualCombatToTheDeath(attacker, defender)) {
            revert Errors.CannotAttackDueToLevelCap();
        }

        // Revert if we're already attacking this target and the defender knows it.
        if (
            attacker.stats.nextTargetIndex == uint8(targetIndex)
                && defender.stats.combatantBitMap & (1 << uint256(attacker.stats.index)) != 0
        ) {
            revert Errors.AlreadyInCombat(attacker.stats.index, defender.stats.index);
        }

        // Log that we instigated combat
        if (_notYetInCombat(attacker, defender)) {
            _logInstigatedCombat(attacker, defender);
        }

        if (attacker.stats.nextTargetIndex != uint8(targetIndex)) {
            attacker.stats.nextTargetIndex = uint8(targetIndex);
            attacker.tracker.updateStats = true;
        }

        // Update monster owner / payor
        if (defender.isMonster()) {
            defender.owner = attacker.owner;
            defender.tracker.updateOwner = true;
        }

        // Flag for combat
        (attacker, defender) = _enterMutualCombatToTheDeath(attacker, defender);

        // Create tasks
        bool scheduledTask = true; // Set as true to assume there's no monster task

        // Only create for attacker and defendant if tasks don't already exist
        if (defender.activeTask == address(0)) {
            (defender, scheduledTask) = _createCombatTask(defender, _cooldown(defender.stats));
        }

        if (scheduledTask && attacker.activeTask == address(0)) {
            (attacker, scheduledTask) = _createCombatTask(attacker, _cooldown(attacker.stats));
        }

        // This is being called by a non-task function, so revert if we failed to schedule the task
        if (!scheduledTask) {
            revert Errors.TaskNotScheduled();
        }

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

        // Store the chat log
        _storeChatLog(player, message);
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

        if (player.inventory.hasWeapon(armorID)) {
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

        player.stats.strength += uint8(newStrength);
        player.stats.vitality += uint8(newVitality);
        player.stats.dexterity += uint8(newDexterity);
        player.stats.quickness += uint8(newQuickness);
        player.stats.sturdiness += uint8(newSturdiness);
        player.stats.luck += uint8(newLuck);

        // NOTE: This won't increase health in combat
        if (player.stats.combatants == 0) {
            player.stats.health = uint16(_maxHealth(player.stats));
        }

        player.tracker.updateStats = true;

        // Return player
        return player;
    }

    function _handleCombatTurn(BattleNad memory attacker)
        internal
        returns (BattleNad memory, bool reschedule, uint256 nextExecutionBlock)
    {
        // Verify that attacker is still alive
        if (attacker.isDead()) {
            attacker = _processAttackerDeath(attacker);
            attacker = _setActiveTask(attacker, address(0));
            return (attacker, false, 0);
        }

        // Apply class adjustments
        attacker = _addClassStatAdjustments(attacker);

        // Attempt to load a defender, exit if no defenders remain
        BattleNad memory defender;
        (attacker, defender.id, defender.stats) = _getTargetIDAndStats(attacker);

        // Start a combat log
        Log memory log = _startCombatLog(attacker, defender);

        if (defender.id == bytes32(0)) {
            (attacker, log) = _regenerateHealth(attacker, log);

            // Store the log
            _storeLog(attacker, log);

            // CASE: No combatants remain
            if (attacker.stats.combatants == 0) {
                attacker = _setActiveTask(attacker, address(0));
                reschedule = false;
                nextExecutionBlock = 0;

                // CASE: Combatant remains, but we must return early
                // NOTE: Might be possible due to running out of gas
            } else {
                reschedule = true;
                nextExecutionBlock = block.number + 1;
            }

            // Save and return
            return (_removeClassStatAdjustments(attacker), reschedule, nextExecutionBlock);
        }

        defender = _addClassStatAdjustments(defender);

        // If it's a monster, update defender's owner to most recent attacker
        if (defender.isMonster()) {
            if (defender.owner != attacker.owner) {
                defender.owner = attacker.owner;
                defender.tracker.updateOwner = true;
            }
        }

        // Load equipment
        attacker = attacker.loadEquipment();
        defender = defender.loadEquipment();

        // Process attack
        (attacker, defender, log) = _attack(attacker, defender, log);

        // Check if defender died and handle that case
        if (defender.tracker.died) {
            log.targetDied = true;

            // Monsters don't earn experience or collect loot
            if (!attacker.isMonster()) {
                (attacker, log) = _earnExperience(attacker, defender.stats.level, defender.isMonster(), log);
                // Only load inventory if defender died
                unchecked {
                    attacker.inventory = inventories[attacker.id];
                }
                (attacker, log) = _handleLoot(attacker, defender, log);
            }

            (attacker, defender, log) = _allocateBalanceInDeath(attacker, defender, log);
            (attacker, defender) = _disengageFromCombat(attacker, defender);
            defender = _processDefenderDeath(defender);

            // If attacker is a monster and it just killed a player and it's still in combat,
            // change attacker's owner to another player
            if (attacker.isMonster() && attacker.stats.combatants != 0) {
                bytes32 newOwnerId;
                (attacker, newOwnerId,) = _getTargetIDAndStats(attacker);
                if (attacker.stats.combatants != 0 && newOwnerId != bytes32(0)) {
                    attacker.owner = owners[newOwnerId];
                    attacker.tracker.updateOwner = true;
                }
            }
        }

        // CASE: All opponents have been defeated
        if (attacker.stats.combatants == 0) {
            attacker.stats.sumOfCombatantLevels = 0;
            reschedule = false;
            nextExecutionBlock = 0;
            attacker = _setActiveTask(attacker, address(0));

            // CASE: Defenders still exist
        } else {
            reschedule = true;
            nextExecutionBlock = block.number + _cooldown(attacker.stats);
        }

        // Handle health regen and storage, then return the necessary data
        (attacker, log) = _regenerateHealth(attacker, log);

        // Store the log
        _storeLog(attacker, log);

        // Store defender
        _storeBattleNad(_removeClassStatAdjustments(defender));

        return (_removeClassStatAdjustments(attacker), reschedule, nextExecutionBlock);
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
        returns (BattleNad memory)
    {
        // Load ability
        attacker.activeAbility = _loadAbility(attacker.id);

        // Cannot use an ability while on cooldown
        if (attacker.activeAbility.taskAddress != address(0)) {
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

        // Apply class adjustments
        attacker = _addClassStatAdjustments(attacker);

        // Attempt to load a defender, exit if no defenders remain
        BattleNad memory defender;
        bool loadedDefender = attacker.activeAbility.targetIndex != 0
            && attacker.activeAbility.targetIndex != uint256(attacker.stats.index);
        if (loadedDefender) {
            defender.id = instances[attacker.stats.depth][attacker.stats.x][attacker.stats.y].combatants[attacker
                .activeAbility
                .targetIndex];

            if (defender.id == bytes32(0)) {
                // Return early if target cant be found
                return (_removeClassStatAdjustments(attacker), false, 0);
            }
            defender = _loadBattleNad(defender.id);

            if (defender.isDead()) {
                // Return early if target cant be found - process their death in regular combat task.
                return (_removeClassStatAdjustments(attacker), false, 0);
            }

            defender = _addClassStatAdjustments(defender);
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
            if (attacker.activeAbility.targetIndex != 0) {
                revert Errors.AbilityCantHaveTarget();
            }
        }

        // Do the ability
        (attacker, defender, reschedule, nextBlock) = _processAbility(attacker, defender);

        // Schedule the task if needed
        if (reschedule) {
            (attacker, reschedule) = _createAbilityTask(attacker, nextBlock);
            if (!reschedule) {
                revert Errors.TaskNotRescheduled();
            }
        }

        // Flag for update
        attacker.tracker.updateActiveAbility = true;

        // Store defender
        if (loadedDefender) {
            defender = _removeClassStatAdjustments(defender);
            _storeBattleNad(defender);
        }

        return (_removeClassStatAdjustments(attacker), reschedule, nextBlock);
    }

    function _forceKill(BattleNad memory combatant) internal returns (uint256 cashedOutShMONShares) {
        if (combatant.stats.x != 0 || combatant.stats.y != 0) {
            _leaveLocation(combatant);
        }

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
        BattleArea memory area = _loadArea(combatant.stats.depth, combatant.stats.x, combatant.stats.y);
        uint256 monsterBitmap = uint256(area.monsterBitMap);
        uint256 combinedBitmap = uint256(area.playerBitMap) | monsterBitmap;

        uint256 combatantBitmap = uint256(combatant.stats.combatantBitMap);
        uint256 combatantBit = 1 << uint256(combatant.stats.index);

        // Flip off this combatant's own bit
        combinedBitmap &= ~combatantBit;

        if (combinedBitmap == 0) {
            combatant.stats.combatantBitMap = 0;
            combatant.stats.nextTargetIndex = 0;
            combatant.stats.combatants = 0;
            combatant.stats.sumOfCombatantLevels = 0;
            combatant.stats.health = uint16(_maxHealth(combatant.stats));
            combatant.tracker.updateStats = true;
            return combatant;
        }

        // Can't have an index of 0, start i at 1.
        for (uint256 i = 1; i < 64; i++) {
            if (gasleft() < 45_000) break;

            uint256 indexBit = 1 << i;

            // Check if in combat
            if (combatantBitmap & indexBit != 0) {
                // If in combat, check if opponent exists
                if (combinedBitmap & indexBit != 0) {
                    BattleNad memory opponent = _loadCombatant(area, i);
                    uint256 opponentBitmap = uint256(opponent.stats.combatantBitMap);

                    // CASE: Opponent isn't in combat with this player
                    if (opponentBitmap & combatantBit == 0) {
                        // pass (remove opponent from this char's combat bitmap)

                        // CASE: Opponent is dead
                    } else if (opponent.isDead()) {
                        // Remove this char from opponent's bitmap
                        opponent.stats.combatantBitMap = uint64(opponentBitmap & ~combatantBit);
                        opponent.tracker.updateStats = true;
                        _storeBattleNad(opponent);
                        //pass (remove opponent from this char's combat bitmap)

                        // CASE: Opponent doesn't have an active task going
                    } else if (opponent.activeTask == address(0)) {
                        // Remove this char from opponent's bitmap
                        opponent.stats.combatantBitMap = uint64(opponentBitmap & ~combatantBit);
                        opponent.tracker.updateStats = true;
                        _storeBattleNad(opponent);
                        // pass (remove opponent from this char's combat bitmap)

                        // CASE: We're forcibly removing opponent from combat - most likely
                        // because combatant is being forceKilled / despawned
                    } else if (forceRemoveCombat) {
                        opponent.stats.combatantBitMap = uint64(opponentBitmap & ~combatantBit);
                        opponent.tracker.updateStats = true;
                        _storeBattleNad(opponent);
                        // pass (remove opponent from this char's combat bitmap)

                        // CASE: Opponent is legitimately in combat with character
                    } else {
                        continue;
                    }
                }

                // If opponent doesn't exist, remove opponent from combat bitmap
                combatantBitmap &= ~indexBit;
                --combatant.stats.combatants;
                if (!combatant.tracker.updateStats) combatant.tracker.updateStats = true;

                // Remove target if it matches
                if (uint256(combatant.stats.nextTargetIndex) == i) {
                    combatant.stats.nextTargetIndex = 0;
                }

                // Check for early break
                if (combatant.stats.combatants == 0) {
                    combatant.stats.combatantBitMap = 0;
                    combatant.stats.nextTargetIndex = 0;
                    combatant.stats.combatants = 0;
                    combatant.stats.sumOfCombatantLevels = 0;
                    combatant.stats.health = uint16(_maxHealth(combatant.stats));
                    combatant.tracker.updateStats = true;
                    return combatant;
                }
            }
        }

        combatant.stats.combatantBitMap = uint64(combatantBitmap);
        return combatant;
    }

    modifier CalledBySelfInTryCatch() {
        if (msg.sender != address(this)) {
            revert Errors.InvalidCaller(msg.sender);
        }
        _;
    }

    modifier NotWhileInCombat(BattleNad memory player) {
        if (player.activeTask != address(0)) {
            revert Errors.CantMoveInCombat();
        } else if (player.isInCombat()) {
            player = _combatCheckLoop(player, false);
            _storeBattleNad(player);
            return;
        }
        _;
    }

    modifier NotWhileDead(BattleNad memory player) {
        if (player.isDead()) {
            revert Errors.CantProcessWhileDead();
        }
        _;
    }
}
