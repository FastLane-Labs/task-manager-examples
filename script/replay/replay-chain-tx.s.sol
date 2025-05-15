// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

/**
 * @title ReplayChainTx
 * @notice Replays a specific transaction fetched by an external script.
 * @dev Reads transaction details (from, to, value, data) and signer PK from environment variables.
 *      Run via the companion shell script (e.g., replay-battle-nads-tx.sh).
 */
contract ReplayChainTx is Script {
    // Transaction details read from environment
    address replayTxFrom;
    address replayTxTo;
    uint256 replayTxValue;
    bytes replayTxInput;
    uint256 replayTxGasLimit; // Gas limit for the transaction call

    function setUp() public {
        // Load transaction details from environment
        replayTxFrom = vm.envAddress("REPLAY_TX_FROM");
        replayTxTo = vm.envAddress("REPLAY_TX_TO");
        replayTxValue = vm.envUint("REPLAY_TX_VALUE"); // Assumes the shell script provides decimal Wei
        replayTxInput = vm.envBytes("REPLAY_TX_INPUT");
        replayTxGasLimit = vm.envUint("REPLAY_TX_GAS_LIMIT");

        if (replayTxFrom == address(0)) {
            revert("Missing or invalid REPLAY_TX_FROM environment variable");
        }
        if (replayTxTo == address(0)) {
            revert("Missing or invalid REPLAY_TX_TO environment variable");
        }
        // Note: replayTxInput can be empty (e.g., for simple value transfers)

        console.log("\n--- Transaction Details from Env --- ");
        console.log("From:          ", replayTxFrom);
        console.log("To:            ", replayTxTo);
        console.log("Value (Wei):   ", replayTxValue);
        // console.logBytes cannot handle very large byte arrays well in output
        if (replayTxInput.length > 0) {
            console.log("Input Data Len:", replayTxInput.length);
        } else {
            console.log("Input Data:    (empty)");
        }
        console.log("Gas Limit:     ", replayTxGasLimit);
        console.log("------------------------------------\n");
    }

    function run() public {
        console.log("--- Starting Transaction Replay Simulation ---");

        // Impersonate the original sender
        console.log("Pranking as original sender:", replayTxFrom);
        vm.startPrank(replayTxFrom);

        // Execute the transaction call
        console.log("Executing call to:", replayTxTo, "with gas limit:", replayTxGasLimit);
        (bool success, bytes memory result) =
            replayTxTo.call{ value: replayTxValue, gas: replayTxGasLimit }(replayTxInput);

        // Stop impersonating
        vm.stopPrank();

        console.log("--- Replay Simulation Finished ---");

        // Report result
        if (success) {
            console.log("Transaction replay SUCCEEDED");
            if (result.length > 0) {
                console.log("Result Data (first 32 bytes):");
                // Log only a portion if it's large
                uint256 logLength = result.length < 32 ? result.length : 32;
                bytes memory resultPrefix = new bytes(logLength);
                for (uint256 i = 0; i < logLength; i++) {
                    resultPrefix[i] = result[i];
                }
                console.logBytes(resultPrefix);
            } else {
                console.log("(No return data)");
            }
        } else {
            console.log("Transaction replay FAILED");
            if (result.length > 0) {
                string memory revertReason = getRevertMsg(result);
                console.log("Revert reason:", revertReason);
            } else {
                console.log("(No revert reason provided)");
            }
            // Optionally revert the script itself on failure
            // revert("Transaction replay failed");
        }
    }

    /**
     * @dev Extract revert reason from failed transaction return data.
     * @param _returnData The return data from the failed call.
     * @return Revert reason as a string, or a default message.
     */
    function getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // Standard Error(string) selector: 0x08c379a0
        if (_returnData.length >= 4 && bytes4(_returnData) == bytes4(keccak256("Error(string)"))) {
            // Skip the 4-byte selector and decode the string
            bytes memory reasonBytes = new bytes(_returnData.length - 4);
            for (uint256 i = 0; i < reasonBytes.length; i++) {
                reasonBytes[i] = _returnData[i + 4];
            }
            // Use abi.decode directly on the sliced bytes
            return abi.decode(reasonBytes, (string));
        }

        // Handle cases with no specific revert message or non-standard errors
        if (_returnData.length == 0) {
            return "Transaction reverted silently (no data).";
        }

        // Fallback for other cases (like Panic codes or custom errors without string)
        // You could add more specific handling here if needed
        return "Transaction reverted (unknown reason or non-string error).";
    }
}
