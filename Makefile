# Include .env file if it exists
-include .env

# Default network and RPC settings
NETWORK ?= monad-testnet
# Extract network type and name from NETWORK variable (e.g., eth-mainnet -> ETH_MAINNET)
NETWORK_UPPER = $(shell echo $(NETWORK) | tr 'a-z-' 'A-Z_')
# Override any existing RPC_URL with the network-specific one
RPC_URL = $($(NETWORK_UPPER)_RPC_URL)
# Default fork block (can be overridden)
FORK_BLOCK ?= latest

# Conditionally set the fork block number flag
ifeq ($(FORK_BLOCK),latest)
  FORK_BLOCK_FLAG = 
else
  FORK_BLOCK_FLAG = --fork-block-number $(FORK_BLOCK)
endif

# Declare all PHONY targets
.PHONY: all clean install build test test-gas format snapshot anvil size update \
        test-deploy-battle-nads deploy-battle-nads test-execute-tasks execute-tasks \
        fork-test-deploy-battle-nads get-session-key test-battle-nads debug-network \
        fork-anvil replay-tx get-character get-battle-nad-lite get-battle-nad-lite-by-id \
        check-mon-balances

# Debug target
debug-network:
	@echo "NETWORK: $(NETWORK)"
	@echo "NETWORK_UPPER: $(NETWORK_UPPER)"
	@echo "RPC_URL: $(RPC_URL)"
	@echo "FORK_BLOCK: $(FORK_BLOCK)"
	@echo "FORK_BLOCK_FLAG: $(FORK_BLOCK_FLAG)"

# Default target
all: clean install build test

# Build and test targets
clean:
	forge clean

install:
	forge install

build:
	forge build

test:
	forge test -vvv

test-gas:
	forge test -vvv --gas-report

# New target for BattleNads tests specifically
test-battle-nads:
	@echo "Running BattleNads tests..."
	forge test --match-contract BattleNads.*Test -vvv

format:
	forge fmt

snapshot:
	forge snapshot

anvil:
	anvil

# Start anvil with fork of the specified network
fork-anvil: debug-network
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Starting anvil with fork of $(NETWORK) at block $(FORK_BLOCK)..."
	anvil --fork-url $(RPC_URL) $(FORK_BLOCK_FLAG)

size:
	forge build --sizes

update:
	forge update 



# Add Battle-Nads deployment targets
test-deploy-battle-nads: debug-network
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "PRIVATE_KEY is not set"; exit 1; fi
	@if [ -z "$(ADDRESS_HUB)" ]; then echo "ADDRESS_HUB is not set"; exit 1; fi
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Testing Battle-Nads deployment on $(NETWORK)..."
	forge script script/battle-nads/deploy-battle-nads.s.sol:DeployBattleNads \
		--rpc-url $(RPC_URL) \
		--code-size-limit 128000 \
		-vvv

deploy-battle-nads: debug-network
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "PRIVATE_KEY is not set"; exit 1; fi
	@if [ -z "$(ADDRESS_HUB)" ]; then echo "ADDRESS_HUB is not set"; exit 1; fi
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Deploying Battle-Nads to $(NETWORK)..."
	forge script script/battle-nads/deploy-battle-nads.s.sol:DeployBattleNads \
		--rpc-url $(RPC_URL) \
		--broadcast \
		--code-size-limit 128000 \
		-vvv

# Get Session Key Data Target
get-session-key: debug-network
	@if [ -z "$(OWNER_ADDRESS)" ]; then \
		echo "Error: OWNER_ADDRESS environment variable must be set (e.g., in .env file or exported)."; \
		echo "Usage: make get-session-key [NETWORK=<network>]"; \
		exit 1; \
	fi
	@if [ -z "$(GETTERS_CONTRACT_ADDRESS)" ]; then \
		echo "Error: GETTERS_CONTRACT_ADDRESS environment variable must be set (e.g., in .env file)."; \
		exit 1; \
	fi
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Getting session key data for owner $(OWNER_ADDRESS) on $(NETWORK)..."
	forge script script/battle-nads/get-session-key-data.s.sol:GetSessionKeyDataScript \
		--rpc-url $(RPC_URL) \
		-vvvv

# Get Character ID Target
get-character: debug-network
	@if [ -z "$(OWNER_ADDRESS)" ]; then \
		echo "Error: OWNER_ADDRESS environment variable must be set (e.g., in .env file or exported)."; \
		echo "Usage: make get-character [NETWORK=<network>]"; \
		exit 1; \
	fi
	@if [ -z "$(GETTERS_CONTRACT_ADDRESS)" ]; then \
		echo "Error: GETTERS_CONTRACT_ADDRESS environment variable must be set (e.g., in .env file)."; \
		exit 1; \
	fi
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Getting character ID for owner $(OWNER_ADDRESS) on $(NETWORK)..."
	forge script script/battle-nads/get-character-id.s.sol:GetCharacterIDScript $(OWNER_ADDRESS) \
		--rpc-url $(RPC_URL) \
		-vvvv

# Get BattleNadLite Data by Character ID Target
get-battle-nad-lite-by-id: debug-network
	@if [ -z "$(CHARACTER_ID)" ]; then \
		echo "Error: CHARACTER_ID environment variable must be set."; \
		echo "Usage: make get-battle-nad-lite-by-id CHARACTER_ID=<character_id> [NETWORK=<network>]"; \
		exit 1; \
	fi
	@if [ -z "$(GETTERS_CONTRACT_ADDRESS)" ]; then \
		echo "Error: GETTERS_CONTRACT_ADDRESS environment variable must be set (e.g., in .env file)."; \
		exit 1; \
	fi
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Getting BattleNadLite data for character ID $(CHARACTER_ID) on $(NETWORK)..."
	forge script script/battle-nads/get-battle-nad-lite.s.sol:GetBattleNadLiteScript --sig "run(bytes32)" $(CHARACTER_ID) \
		--rpc-url $(RPC_URL) \
		-vvvv

# Add execute-tasks targets
test-execute-tasks: debug-network
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "PRIVATE_KEY is not set"; exit 1; fi
	@if [ -z "$(ADDRESS_HUB)" ]; then echo "ADDRESS_HUB is not set"; exit 1; fi
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Testing task execution on $(NETWORK)..."
	forge script script/task-manager/execute-tasks.s.sol:ExecuteTasksScript \
		--rpc-url $(RPC_URL) \
		-vvv

execute-tasks: debug-network
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "PRIVATE_KEY is not set"; exit 1; fi
	@if [ -z "$(ADDRESS_HUB)" ]; then echo "ADDRESS_HUB is not set"; exit 1; fi
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Executing tasks in TaskManager on $(NETWORK)..."
	forge script script/task-manager/execute-tasks.s.sol:ExecuteTasksScript \
		--rpc-url $(RPC_URL) \
		--broadcast \
		-vvv

# Check MON Balances Target
check-mon-balances: debug-network
	@if [ -z "$(RPC_URL)" ]; then echo "No RPC URL found for network $(NETWORK)"; exit 1; fi
	@echo "Checking MON balances on $(NETWORK)..."
	forge script script/task-manager/check-mon-balances.s.sol:CheckMonBalancesScript \
		--rpc-url $(RPC_URL) \
		-vvv

# Transaction Replay Target
replay-tx:
	@if [ -z "$(TARGET_TX_HASH)" ]; then \
		echo "Error: TARGET_TX_HASH variable must be set."; \
		echo "Usage: make replay-tx TARGET_TX_HASH=<hash> [FORK_REF_TX_HASH=<hash>] [NETWORK=<network>]"; \
		exit 1; \
	fi
	@echo "Replaying transaction $(TARGET_TX_HASH) on $(NETWORK)..."
	@CMD="./script/replay/replay-chain-tx.sh -t $(TARGET_TX_HASH)"; \
	if [ -n "$(FORK_REF_TX_HASH)" ]; then \
		CMD="$$CMD -ftx $(FORK_REF_TX_HASH)"; \
	fi; \
	RPC_TO_USE=$(firstword $($(NETWORK_UPPER)_RPC_URL) $(DEFAULT_RPC_URL)); \
	if [ -n "$(RPC_TO_USE)" ]; then \
		CMD="$$CMD -r $(RPC_TO_USE)"; \
	fi; \
	echo "Executing: $$CMD"; \
	$$CMD