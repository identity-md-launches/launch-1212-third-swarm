# SWARMLER test coverage

Run the complete offline suite with `forge build` and `forge test`. All test
dependencies are existing committed files under `vendor/`. No environment values
are written by the tests, and run counts are declared in Solidity comments.

The hook suites deploy the actual vendored Uniswap v4 PoolManager and CREATE2-mine
the hook's permission bits. Both token address orderings exercise exact-input and
exact-output buys/sells, price-limited partial fills, fee claims, sweeps, and batches.
Swap events independently establish the pool's raw BalanceDelta and static 12500
LP fee; settlement checks include router refunds, hook claims, and manager locking.

Additional failure checks in `support/HookFailureChecks.sol` cover:

- The largest accepted specified request and rejection of the next integer in all
  four swap modes. A 1000-run property proves larger unfilled requests cannot
  change balances, fees, or the actual fill.
- Zero-liquidity swaps, insufficient settlement funds, failed burn transfers,
  rollback of fees/references/cooldowns, and successful retries.
- Dust fills after an earlier successful batch, sweeps during batch cooldown,
  and reference updates after a batch changes the previous block's closing price.

Launch tests also verify that invalid opening prices and attempts to initialize
different pool terms do not poison the legitimate launch. Transfer failures are
injected only in dedicated rollback tests; the ordinary suites use the original
SWARMLER token. Fault injection does not claim that this fixed token can be paused.

The hook invariants run 256 sequences of 64 actions in each address ordering, with
unexpected reverts treated as failures. Actions change liquidity (including zero
and dust), swap with bounded price limits, sweep, batch, and advance time/blocks.
Independent accounting checks fees, claims, burns, both currency supplies,
reference history, stale budgets, and cooldown eligibility. A separate custom
ERC-20 handler checks balances and allowances after random approvals, transfers,
delegated transfers, self-transfers, revocations, and rejected calls.

`SWARMLERFork.t.sol` inherits the integration and failure checks for Ethereum's
deployed PoolManager and IMD. To run it against a pinned, post-deployment block:

```sh
forge test --fork-url "$MAINNET_RPC_URL" --fork-block-number "$MAINNET_FORK_BLOCK" \
  --match-path test/SWARMLERFork.t.sol
```

Fork suites explicitly skip without an active fork. No mainnet run was available
in this task: no RPC was configured, and three public RPC endpoints returned HTTP
403. Offline results therefore establish local PoolManager integration, not the
current deployed IMD contract's behavior. No implementation defect was reproduced.
