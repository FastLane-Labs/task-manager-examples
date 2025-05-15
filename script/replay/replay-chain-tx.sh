#!/bin/bash

# Transaction Replay Helper Script
# Fetches transaction details from an RPC, prepares environment,
# and runs the Foundry script simulation.
# Supports two modes:
# 1. Default: Forks BEFORE the target transaction's block using forge script.
# 2. Fork-at-hash: Forks AFTER a specified reference transaction using anvil.

# --- Configuration ---
DEFAULT_RPC_URL="https://rpc-testnet.monadinfra.com/rpc/Dp2u0HD0WxKQEvgmaiT4dwCeH9J14C24"
SOLIDITY_SCRIPT_PATH="script/replay/replay-chain-tx.s.sol:ReplayChainTx"
ANVIL_RPC_URL="http://127.0.0.1:8545" # Default Anvil URL

# --- Helper Functions ---
function show_help {
  echo "Transaction Replay Helper"
  echo ""
  echo "Usage: $0 -t TARGET_TX_HASH [-ftx FORK_REF_TX_HASH] [-a EXPECTED_TARGET_ADDRESS] [-r RPC_URL]"
  echo ""
  echo "Required arguments:"
  echo "  -t, --tx-hash TARGET_TX_HASH     Transaction hash to simulate"
  echo ""
  echo "Optional arguments:"
  echo "  -ftx, --fork-tx-hash HASH      Fork AFTER this specific transaction hash using Anvil"
  echo "  -a, --address ADDRESS            Expected target contract address (for verification of TARGET_TX_HASH)"
  echo "  -r, --rpc-url RPC_URL            RPC URL to use (default: $DEFAULT_RPC_URL)"
  echo "  -h, --help                       Show this help message"
}

# --- Argument Parsing ---
RPC_URL="$DEFAULT_RPC_URL"
EXPECTED_TARGET_ADDRESS="" # Optional
TARGET_TX_HASH=""
FORK_REF_TX_HASH="" # Optional

while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--tx-hash)
      TARGET_TX_HASH="$2"
      shift 2
      ;;
    -ftx|--fork-tx-hash)
      FORK_REF_TX_HASH="$2"
      shift 2
      ;;
    -a|--address)
      EXPECTED_TARGET_ADDRESS="$2"
      shift 2
      ;;
    -r|--rpc-url)
      RPC_URL="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# --- Validation ---
if [ -z "$TARGET_TX_HASH" ]; then
  echo "Error: Target transaction hash (-t, --tx-hash) is required"
  show_help
  exit 1
fi

# Check for required tools (anvil needed only if -ftx is used)
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install curl."
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq."
    exit 1
fi
if ! command -v forge &> /dev/null; then
    echo "Error: forge (Foundry) is not installed. Please install Foundry."
    exit 1
fi
if ! command -v cast &> /dev/null; then
    echo "Error: cast (Foundry) is not installed or not in PATH. Please install Foundry."
    exit 1
fi
if [ ! -z "$FORK_REF_TX_HASH" ]; then
  if ! command -v anvil &> /dev/null; then
      echo "Error: anvil is required when using -ftx flag. Please install Foundry."
      exit 1
  fi
fi

# --- Fetch Target Transaction Details (for Replay Info) ---
echo "Fetching target transaction ($TARGET_TX_HASH) details for replay parameters..."
JSON_PAYLOAD_TARGET=$(cat <<EOF
{"jsonrpc":"2.0","method":"eth_getTransactionByHash","params":["$TARGET_TX_HASH"],"id":1}
EOF
)
RESPONSE_TARGET=$(curl -s -X POST "$RPC_URL" -H "Content-Type: application/json" -d "$JSON_PAYLOAD_TARGET")
ERROR_MSG_TARGET=$(echo "$RESPONSE_TARGET" | jq -r '.error.message')
if [ "$ERROR_MSG_TARGET" != "null" ]; then echo "Error fetching target transaction: $ERROR_MSG_TARGET"; exit 1; fi
TX_DATA_TARGET=$(echo "$RESPONSE_TARGET" | jq '.result')
if [ "$TX_DATA_TARGET" == "null" ]; then echo "Error: Target transaction $TARGET_TX_HASH not found."; exit 1; fi

REPLAY_TX_FROM_RAW=$(echo "$TX_DATA_TARGET" | jq -r '.from')
REPLAY_TX_TO_RAW=$(echo "$TX_DATA_TARGET" | jq -r '.to')
REPLAY_TX_VALUE_HEX=$(echo "$TX_DATA_TARGET" | jq -r '.value')
REPLAY_TX_INPUT=$(echo "$TX_DATA_TARGET" | jq -r '.input')
TARGET_BLOCK_HEX=$(echo "$TX_DATA_TARGET" | jq -r '.blockNumber') # Block of the tx we are replaying
TARGET_TX_INDEX_HEX=$(echo "$TX_DATA_TARGET" | jq -r '.transactionIndex') # Index of the tx we are replaying
REPLAY_TX_GAS_LIMIT_HEX=$(echo "$TX_DATA_TARGET" | jq -r '.gas') # Gas limit of the tx

# --- Process Replay Parameters ---
# Checksum addresses, process value (same as before)
# ... (checksum REPLAY_TX_FROM_RAW -> REPLAY_TX_FROM) ...
# ... (checksum REPLAY_TX_TO_RAW -> REPLAY_TX_TO, handle null) ...
# ... (process REPLAY_TX_VALUE_HEX -> REPLAY_TX_VALUE) ...
# (Assuming checksum/value processing code from previous state is here)
# Example placeholders:
if [ "$REPLAY_TX_FROM_RAW" != "null" ] && [ -n "$REPLAY_TX_FROM_RAW" ]; then REPLAY_TX_FROM=$(cast to-check-sum-address "$REPLAY_TX_FROM_RAW"); else echo "Error extracting FROM"; exit 1; fi
if [ "$REPLAY_TX_TO_RAW" != "null" ] && [ -n "$REPLAY_TX_TO_RAW" ]; then REPLAY_TX_TO=$(cast to-check-sum-address "$REPLAY_TX_TO_RAW"); else REPLAY_TX_TO="0x0000000000000000000000000000000000000000"; fi
if [[ "$REPLAY_TX_VALUE_HEX" == "0x"* ]]; then REPLAY_TX_VALUE=$((16#${REPLAY_TX_VALUE_HEX#0x})); else REPLAY_TX_VALUE=0; fi
if [[ "$REPLAY_TX_GAS_LIMIT_HEX" == "0x"* ]]; then REPLAY_TX_GAS_LIMIT=$((16#${REPLAY_TX_GAS_LIMIT_HEX#0x})); else echo "Error extracting GAS LIMIT"; exit 1; fi
export REPLAY_TX_FROM REPLAY_TX_TO REPLAY_TX_VALUE REPLAY_TX_INPUT REPLAY_TX_GAS_LIMIT

# --- Conditional Forking Logic --- 
ANVIL_PID=""
FORGE_RPC_URL="$RPC_URL" # Default to original RPC
FORGE_FORK_BLOCK_FLAG="" # Default to no fork block flag for forge

# Function to clean up Anvil on exit (only used in anvil mode)
anvil_cleanup() {
  if [ ! -z "$ANVIL_PID" ]; then
    echo "Stopping background Anvil node (PID: $ANVIL_PID)..."
    kill $ANVIL_PID 2>/dev/null # This kills the process
  fi
}

if [ -z "$FORK_REF_TX_HASH" ]; then
  # --- Mode 1: Standard Forge Fork (Before Target TX Block) ---
  echo "Mode: Standard fork before target transaction block."
  TX_BLOCK_NUMBER=-1
  if [ "$TARGET_BLOCK_HEX" != "null" ] && [ "$TARGET_BLOCK_HEX" != "0x" ]; then
    TX_BLOCK_NUMBER=$((16#${TARGET_BLOCK_HEX#0x}))
    if [ $TX_BLOCK_NUMBER -eq 0 ]; then echo "Error: Target TX in genesis block."; exit 1; fi
    FORK_BLOCK_NUMBER=$(($TX_BLOCK_NUMBER - 1))
    echo "Target TX block: $TX_BLOCK_NUMBER. Forking at block: $FORK_BLOCK_NUMBER."
    FORGE_FORK_BLOCK_FLAG="--fork-block-number $FORK_BLOCK_NUMBER"
  else
    echo "Error: Target TX block number not found."; exit 1;
  fi

else
  # --- Mode 2: Anvil Fork (At Fork Ref TX Hash) ---
  echo "Mode: Anvil fork after reference transaction hash."
  echo "Fetching fork reference transaction ($FORK_REF_TX_HASH) details..."
  JSON_PAYLOAD_FORK=$(cat <<EOF
{"jsonrpc":"2.0","method":"eth_getTransactionByHash","params":["$FORK_REF_TX_HASH"],"id":2}
EOF
)
  RESPONSE_FORK=$(curl -s -X POST "$RPC_URL" -H "Content-Type: application/json" -d "$JSON_PAYLOAD_FORK")
  ERROR_MSG_FORK=$(echo "$RESPONSE_FORK" | jq -r '.error.message')
  if [ "$ERROR_MSG_FORK" != "null" ]; then echo "Error fetching fork ref transaction: $ERROR_MSG_FORK"; exit 1; fi
  TX_DATA_FORK=$(echo "$RESPONSE_FORK" | jq '.result')
  if [ "$TX_DATA_FORK" == "null" ]; then echo "Error: Fork reference transaction $FORK_REF_TX_HASH not found."; exit 1; fi
  FORK_REF_BLOCK_HEX=$(echo "$TX_DATA_FORK" | jq -r '.blockNumber')
  if [ "$FORK_REF_BLOCK_HEX" == "null" ] || [ "$FORK_REF_BLOCK_HEX" == "0x" ]; then echo "Error: Fork ref TX block not found."; exit 1; fi
  FORK_REF_BLOCK_NUMBER=$((16#${FORK_REF_BLOCK_HEX#0x}))
  echo "Fork reference TX is in block: $FORK_REF_BLOCK_NUMBER"

  # Setup trap for anvil cleanup
  trap anvil_cleanup EXIT

  # Check if Anvil port is already in use
  echo "Checking if Anvil port ($ANVIL_RPC_URL) is in use..."
  # Use lsof to check for listening process on the port (e.g., 8545)
  PORT=$(echo $ANVIL_RPC_URL | sed 's/.*://') # Extract port number
  if lsof -iTCP:$PORT -sTCP:LISTEN -P -t >/dev/null ; then
      echo "Error: Port $PORT is already in use. Please stop the existing process (e.g., kill $(lsof -iTCP:$PORT -sTCP:LISTEN -P -t)) and try again."
      trap - EXIT # Remove trap before exiting
      exit 1
  fi

  echo "Starting local Anvil fork after $FORK_REF_TX_HASH..."
  # Construct anvil command using only fork-url and fork-transaction-hash
  ANVIL_CMD="anvil --fork-url $RPC_URL --fork-transaction-hash $FORK_REF_TX_HASH --silent"
  echo "Executing: $ANVIL_CMD"
  $ANVIL_CMD & 
  ANVIL_PID=$!
  echo "Waiting for Anvil to start (PID: $ANVIL_PID)..."
  sleep 5 # Adjust if needed
  if ! kill -0 $ANVIL_PID 2>/dev/null; then echo "Error: Failed to start Anvil."; trap - EXIT; exit 1; fi
  echo "Anvil started. Script will target $ANVIL_RPC_URL"
  FORGE_RPC_URL="$ANVIL_RPC_URL" # Override RPC for forge script
  # FORGE_FORK_BLOCK_FLAG remains empty
fi

# --- Display Final Replay Details --- 
echo ""
echo "--- Final Replay Execution Plan ---"
echo "  Target TX:      $TARGET_TX_HASH"
echo "  Simulate From:  ${REPLAY_TX_FROM}"
echo "  Simulate To:    ${REPLAY_TX_TO}"
echo "  Simulate Value: ${REPLAY_TX_VALUE} (Wei)"
echo "  Simulate Input: ${REPLAY_TX_INPUT:0:66}..."
echo "  Simulate Gas:   ${REPLAY_TX_GAS_LIMIT}"
echo "  Forge RPC URL:  $FORGE_RPC_URL"
echo "  Forge Fork Flag:$FORGE_FORK_BLOCK_FLAG"
echo "  Solidity Script:$SOLIDITY_SCRIPT_PATH"
echo "---------------------------------"
echo ""

# --- Execute Foundry Script ---
echo "Running Foundry script simulation..."

# Construct the forge script command based on mode
FORGE_CMD="forge script $SOLIDITY_SCRIPT_PATH --rpc-url $FORGE_RPC_URL $FORGE_FORK_BLOCK_FLAG -vvvv"

echo "Executing: $FORGE_CMD"
echo ""

eval $FORGE_CMD
EXIT_CODE=$?

# Ensure trap is removed if we are in anvil mode and exited normally
# Trap is automatically removed on EXIT, removing this manual removal
# if [ ! -z "$ANVIL_PID" ]; then
#   trap - EXIT
# fi

if [ $EXIT_CODE -ne 0 ]; then
  echo ""
  echo "Error: Foundry script simulation failed with exit code $EXIT_CODE."
  exit $EXIT_CODE
else
  echo ""
  echo "Foundry script simulation completed successfully."
fi

exit 0 