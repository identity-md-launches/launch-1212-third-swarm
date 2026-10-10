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

The stale-reference regression checks now fuzz first touches by a swap or sweep,
then favorable/adverse same-block price moves, across the 50/51-block boundary.
Both address orderings run 1000 cases. The hook invariants also verify the emitted
300 bps limit against independently recorded reference history by cross
multiplication, actual pool-price movement, partial-fill termination, skipped
batches, and the single batch swap's pool and sender. They reject a same-block
price ratchet even if fee claims and the batch budget still balance correctly.

As a negative control, an isolated scratch copy restored the previously fixed
`anchor = current` stale-price fallback. With seed `0x737761726d6c6572`, the new
fuzz property and strengthened invariants failed in both token orderings. This
was a deliberate regression experiment, not a defect in the current source.

`SWARMLERFork.t.sol` inherits the integration and failure checks for Ethereum's
deployed PoolManager and IMD. To run it against a pinned, post-deployment block:

```sh
forge test --fork-url "$MAINNET_RPC_URL" --fork-block-number "$MAINNET_FORK_BLOCK" \
  --match-path test/SWARMLERFork.t.sol
```

Fork suites explicitly skip without an active fork. In this revision, all 88 fork
tests passed against Ethereum PoolManager and IMD at block **26158741**, hash
`0x6d497061de2131a55affe21622852880fe9f42763f2c83bc77f64c06538df8ec`, using
`https://ethereum-rpc.publicnode.com`. This supersedes the previous round's
unavailable fork run. Fork fuzz properties ran 256 cases each; the local versions
run 1000 cases each. The fork fixture funds the test trader with `deal` and deploys
a new SWARMLER pool; it uses the real paired token and PoolManager code and storage.
No defect in the current implementation was reproduced.
