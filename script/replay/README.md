# Transaction Replay Helper Script (`replay-chain-tx.sh`)

## Purpose

This script simulates a target Ethereum transaction by replaying its parameters (`from`, `to`, `value`, `input`) on a forked environment. It allows you to analyze the transaction's behavior without needing a private key or broadcasting.

The script supports two primary forking modes:

1.  **Default Mode (Fork Before Block):** Forks the chain using `forge script` at the block *before* the target transaction was mined. This is useful for seeing the state just prior to the block starting.
2.  **Fork-at-Hash Mode (Fork After Reference TX):** Uses `anvil` to fork the chain at the state immediately *after* a specified *reference* transaction hash completed. The target transaction is then simulated against this precise state provided by the local Anvil node.

## Dependencies

-   `curl`: For making RPC requests.
-   `jq`: For parsing JSON RPC responses.
-   `foundry`: Specifically `forge`, `cast`, and `anvil` commands.

## Usage

```bash
./script/replay/replay-chain-tx.sh -t TARGET_TX_HASH [OPTIONS]
```

**Required Arguments:**

-   `-t`, `--tx-hash TARGET_TX_HASH`: The hash of the transaction you want to simulate.

**Optional Arguments:**

-   `-ftx`, `--fork-tx-hash HASH`: **(Activates Anvil Mode)** The hash of a *reference* transaction. If provided, the script will start a local Anvil node forked to the state immediately *after* this reference transaction hash completed. The target transaction (`-t`) will then be simulated against this local Anvil node.
-   `-a`, `--address ADDRESS`: The expected target contract address for the *target* transaction (`-t`). Used for an optional verification check.
-   `-r`, `--rpc-url RPC_URL`: The RPC URL of the network to fetch data from and fork. Defaults to the value set in the script (`DEFAULT_RPC_URL`).
-   `-h`, `--help`: Show the help message.

## How it Works

1.  **Fetch Target TX Data:** Retrieves details (`from`, `to`, `value`, `input`, `blockNumber`) for the `-t TARGET_TX_HASH`.
2.  **Prepare Replay Parameters:** Checksums addresses and prepares the data needed for the simulation.
3.  **Conditional Forking:**
    *   **Default Mode:** Calculates the block number *before* the target transaction (`blockNumber - 1`).
    *   **Anvil Mode (`-ftx` used):** Fetches the block number for the `-ftx FORK_REF_TX_HASH`. Starts `anvil` in the background forked using `--fork-transaction-hash` with the reference hash.
4.  **Set Environment:** Exports `REPLAY_TX_FROM`, `REPLAY_TX_TO`, `REPLAY_TX_VALUE`, `REPLAY_TX_INPUT` environment variables.
5.  **Execute Simulation:** Runs the associated Solidity script (`script/replay/replay-chain-tx.s.sol`) using `forge script`:
    *   **Default Mode:** Targets the original RPC URL with `--fork-block-number <block-1>`.
    *   **Anvil Mode:** Targets the local Anvil RPC (`http://127.0.0.1:8545`) with no fork flags.
6.  **Cleanup (Anvil Mode):** Automatically stops the background Anvil process when the script finishes.

## Associated Solidity Script

The bash script executes the simulation logic defined in:
`script/replay/replay-chain-tx.s.sol`

This Solidity script reads the `REPLAY_*` environment variables and uses `vm.prank` to simulate the transaction call.

## Examples

**Example 1: Default Mode (Fork before block)**

Simulate transaction `0xabc...` using the state before its block started.

```bash
./script/replay/replay-chain-tx.sh -t 0xabc...
```

**Example 2: Anvil Fork-at-Hash Mode**

Simulate transaction `0xdef...` using the state that existed immediately *after* transaction `0x123...` completed.

```bash
./script/replay/replay-chain-tx.sh -t 0xdef... -ftx 0x123...
```

**Example 3: Specifying RPC and Expected Address**

```bash
./script/replay/replay-chain-tx.sh \
  -t 0xabc... \
  -a 0xContractAddress... \
  -r https://your-mainnet-rpc.com
``` 