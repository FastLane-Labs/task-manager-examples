// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Inherit common setup and helpers
import { BattleNadsBaseTest } from "./helpers/BattleNadsBaseTest.sol";

// Specific imports for this test file
import { SessionKeyData } from "lib/fastlane-contracts/src/common/relay/types/GasRelayTypes.sol";
import { BattleNad, DataFeed, LogType } from "src/battle-nads/Types.sol";
import { Errors } from "src/battle-nads/libraries/Errors.sol";
import { console } from "forge-std/console.sol";

// Tests focusing on Zone Chat functionality with Session Keys
contract BattleNadsZoneChatTest is BattleNadsBaseTest {

    // Test variables
    bytes32 private chatCharacterId;
    address private chatUser;
    address private chatSessionKey;
    string private testMessage = "Hello from the zone!";
    
    // Constants
    uint256 private constant TEN_BLOCKS = 10; // 10 minute window assuming high block rate

    function setUp() public override {
        // Call the base setup first
        super.setUp();
        

        character4 = _createCharacterAndSpawn(4, "ChatTester", 6, 6, 5, 5, 5, 5, userSessionKey4, uint64(type(uint64).max)); // Use session key for Attacker

        // Use user4 and sessionKey4 for our chat tests
        chatUser = user4;
        chatSessionKey = userSessionKey4;
        chatCharacterId = character4;
        
    }

    function test_ZoneChat_WithSessionKey() public {   

        require(chatCharacterId != bytes32(0), "Setup: Character 4 not created");

        // Ensure character spawned
        BattleNad memory nad_check_spawn = _battleNad(4);
        require(nad_check_spawn.stats.x != 0 || nad_check_spawn.stats.y != 0, "Setup: Character 4 did not spawn");


        // Verify session key is active
        SessionKeyData memory sessionData = battleNads.getCurrentSessionKeyData(chatUser);
        assertEq(sessionData.key, chatSessionKey, "Session key should be set");
        assertEq(sessionData.owner, chatUser, "Owner should be set correctly");
        
        // 3. Top up the session key balance to cover gas costs
        uint256 shortfall = battleNads.shortfallToRecommendedBalanceInMON(chatCharacterId);
        if (shortfall > 0) {
            vm.prank(chatUser);
            battleNads.replenishGasBalance{ value: shortfall }();
        }
        
        // 4. Use session key to send a chat message
        vm.prank(chatSessionKey);
        battleNads.zoneChat(chatCharacterId, testMessage);
        
        // 5. Roll forward to ensure the chat is processed
        _rollForward(1);
        
        // 6. Retrieve and verify chat message from data feeds
        // Use current block as end and look back 10 minutes worth of blocks
        _verifyZoneChatMessage(chatUser, testMessage);
    }
    
    function test_ZoneChat_DirectOwner() public {
        
        require(chatCharacterId != bytes32(0), "Setup: Character 4 not created");

        // Ensure character spawned
        BattleNad memory nad_check_spawn = _battleNad(4);
        require(nad_check_spawn.stats.x != 0 || nad_check_spawn.stats.y != 0, "Setup: Character 4 did not spawn");
        
        // 3. Send chat message directly from owner
        vm.prank(chatUser);
        battleNads.zoneChat(chatCharacterId, testMessage);
        
        // 4. Roll forward to ensure the chat is processed
        _rollForward(1);
        
        // 5. Retrieve and verify chat message from data feeds
        _verifyZoneChatMessage(chatUser, testMessage);
    }
    
    function test_ZoneChat_Unauthorized() public {
        
        require(chatCharacterId != bytes32(0), "Setup: Character 4 not created");

        // Ensure character spawned
        BattleNad memory nad_check_spawn = _battleNad(4);
        require(nad_check_spawn.stats.x != 0 || nad_check_spawn.stats.y != 0, "Setup: Character 4 did not spawn");
        
        // 3. Try to send chat message from unauthorized address (user2)
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidCharacterOwner.selector, chatCharacterId, chatUser));
        battleNads.zoneChat(chatCharacterId, testMessage);
    }
    
    function test_ZoneChat_UpdateSessionKey() public {
        require(chatCharacterId != bytes32(0), "Setup: Character 4 not created");

        // Ensure character spawned
        BattleNad memory nad_check_spawn = _battleNad(4);
        require(nad_check_spawn.stats.x != 0 || nad_check_spawn.stats.y != 0, "Setup: Character 4 did not spawn");
        
        // 3. Update with session key
        uint64 sessionKeyExpiration = uint64(block.timestamp + 1 days);
        
        vm.prank(chatUser);
        battleNads.updateSessionKey(chatSessionKey, sessionKeyExpiration);
        
        // 4. Roll forward to ensure update completes
        _rollForward(1);
        
        // 5. Top up session key balance
        uint256 shortfall = battleNads.shortfallToRecommendedBalanceInMON(chatCharacterId);
        if (shortfall > 0) {
            vm.prank(chatUser);
            battleNads.replenishGasBalance{ value: shortfall }();
        }
        
        // 6. Send chat with session key
        vm.prank(chatSessionKey);
        battleNads.zoneChat(chatCharacterId, testMessage);
        
        // 7. Roll forward and verify
        _rollForward(1);
        _verifyZoneChatMessage(chatUser, testMessage);
    }
    
    // Helper to verify a zone chat message appears in data feeds
    function _verifyZoneChatMessage(
        address owner, 
        string memory expectedMessage
    ) internal view {
        // Calculate block range - current block as end, and looking back 10 minutes
        uint256 endBlock = block.number;
        uint256 startBlock = endBlock > TEN_BLOCKS ? endBlock - TEN_BLOCKS : 0;
        
        console.log("Searching for chat message from block", startBlock, "to", endBlock);
        
        // Get the data feeds for the character's owner within the block range
        DataFeed[] memory dataFeeds = battleNads.getDataFeed(owner, startBlock, endBlock);
        
        console.log("Number of data feeds received:", dataFeeds.length);
        
        // Look for our chat message in the data feeds
        bool found = false;
        for (uint256 i = 0; i < dataFeeds.length; i++) {
            DataFeed memory feed = dataFeeds[i];
            console.log("Data feed block:", feed.blockNumber);
            console.log("Chat logs length:", feed.chatLogs.length);
            
            // Check the chat logs array in this data feed
            for (uint256 j = 0; j < feed.chatLogs.length; j++) {
                string memory chatMessage = feed.chatLogs[j];
                console.log("Chat message:", chatMessage);
                
                // Compare with expected message
                if (keccak256(bytes(chatMessage)) == keccak256(bytes(expectedMessage))) {
                    found = true;
                    break;
                }
            }
            
            if (found) break;
        }
        
        assertTrue(found, "Chat message not found in data feeds");
    }
} 