# Third Swarm launch contracts

`src/SWARMLER.sol` and `src/SWARMLERHook.sol` implement the SIMD-LAUNCH assignment. The accepted logo and website packages remain intact. The authoritative mechanics are M1; this implementation does not use the older background reference's in-callback conversion to ETH.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Network | Ethereum mainnet |
| Token contract / metadata | `SWARMLER` / Third Swarm / SWARMLER / 18 decimals |
| Supply | Exactly 1,000,000,000 tokens, or `10^27` units, minted once to the token deployer |
| Hook contract | `SWARMLERHook`, deployed directly using CREATE2 |
| Hook constructor | `(IPoolManager manager_, address token_)`, manifest `['$poolManager', '$token']` |
| PoolManager argument | `0x000000000004444c5dc75cB358380D2e3dE08A90` |
| IMD, fixed in hook | `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Recipient, fixed in hook | `0x000000000000000000000000000000000000dEaD` |
| Pool | Sorted SWARMLER and IMD addresses, fee `12500`, tick spacing `60`, this hook |
| Manifest opening price | `79228162514264337593543950336`, provenance only |
| Compiler | Existing root configuration: Solidity 0.8.26, Cancun, optimizer 200 runs, bytecode hash none |

The factory deploys the token before the hook, supplies its address, initializes the pool at the price derived from the launch economics, and handles supply distribution. All `10^27` units initially belong to the factory. The token and hook make no swarm allocation: the factory sends the 10% through its Merkle distributor, seeds liquidity, and handles any remainder. There is no owner, setter, mint-after-construction, pause, proxy, delegatecall, selfdestruct, or upgrade authority in either launch contract. The constructor makes no external call and works before other contracts have code.

The root `launch.json` uses exactly the requested manifest shape. Deployment must resolve the two constructor placeholders to the actual manager and freshly deployed token, not substitute a placeholder address. No recipient, oracle, router, keeper, or factory address is missing from the implementation.

## Permission address and deployment sequence

The low 14 bits of the hook's address must be **`0x20c4`**:

| Permission | Bit value |
| --- | --- |
| `beforeInitialize` | `0x2000` |
| `beforeSwap` | `0x0080` |
| `afterSwap` | `0x0040` |
| `afterSwapReturnDelta` | `0x0004` |

All other permission flags are false, including `beforeSwapReturnDelta`. `getHookPermissions()` reports this exact set. The constructor rejects an incorrectly mined address. No wrapper or proxy is involved.

1. Build the token and hook with the unchanged root configuration.
2. Deploy `SWARMLER` through the launch factory, which receives the entire supply.
3. Form `initcode = SWARMLERHook.creationCode || abi.encode(poolManager, token)`.
4. Using the factory's **actual CREATE2 deployer address**, search salts until the last 20 bytes of `keccak256(0xff || deployer || salt || keccak256(initcode))` have low 14 bits `0x20c4`. A salt depends on the exact compiler output and both arguments; never reuse one from a test fixture. `test/support/HookFixture.sol` contains an executable mining/deployment example.
5. Deploy the hook directly and initialize its exact canonical pool, atomically in the factory transaction. The enabled initialization callback prevents initializing the predicted pool before the hook exists. It authenticates PoolManager, accepts only this token/IMD/fee/spacing/hook key, and seeds the reference from the supplied initial price. Initialization is permissionless for this single canonical key; deployment and initialization must remain atomic.
6. Seed and distribute using the factory's launch procedure. Verify source, bytecode, constructor arguments, permission bits, and pool key against the built artifacts.

No deployment or broadcast was performed by this assignment. CREATE2 mining is deliberately part of deployment: the future token and deployer addresses are needed to compute the final salt.

## Actual-fill hook fees

The pool retains its **static 1.25% LP fee**. The hook returns no specified-side adjustment and no LP fee override in `beforeSwap`. It never invokes `updateDynamicLPFee`.

In `afterSwap`, let `d` be the actual pool `BalanceDelta` on the **unspecified** currency. The extra fee is `floor(abs(d) / 100)`:

| Trade | Unspecified currency | Fee effect |
| --- | --- | --- |
| Exact-input buy | SWARMLER output | User receives 99% of the actual gross output, up to rounding |
| Exact-input sell | IMD output | User receives 99% of the actual gross output, up to rounding |
| Exact-output buy | IMD input | User pays an additional 1% of the actual input, up to rounding |
| Exact-output sell | SWARMLER input | User pays an additional 1% of the actual input, up to rounding |

The unspecified currency is currency0 exactly when `(amountSpecified < 0) != zeroForOne`. Token address ordering is never assumed. There is no reservation, so price-limited partial fills need no refund: only the actual delta is taxed. Fees below one unit round down to zero. Hook data and the router's identity cannot select a fee exemption or recipient.

For each fee, PoolManager mints an ERC-6909 claim to the hook. The mint creates a transient hook debit; the positive `afterSwapReturnDelta` cancels it and shifts the fee to the router's delta. There is no ERC-20 transfer, redemption, buyback, or burn inside a swap callback. In particular, an exact-output buy succeeds even if the manager has no IMD before the router pays its input. The test suite includes a freshly deployed manager with liquidity seeded only in SWARMLER.

`pending()` reports accrued IMD claim units; `pendingBurn()` reports accrued SWARMLER claim units. These counters track collected fees, not unsolicited ERC-20 or ERC-6909 donations. Do not transfer assets directly to the hook: there is no general rescue function.

Normal swaps are independent of buyback cooldown, liquidity, and execution success. Core PoolManager validity and settlement rules still apply. A specified amount whose magnitude plus the nominal 1% would exceed `int256.max` reverts with `UnrepresentableFee`. Other representable enormous requests can partially fill at a price limit and pay fees only on the fill.

## Sweeps and buybacks

Anyone may call `sweep()` in a separate unlock to burn all accrued SWARMLER claims and take that amount directly from PoolManager to the dead address. It returns the amount and emits `Swept`. Repeated empty sweeps return zero. The ERC-20's `totalSupply()` stays fixed; “burn” means the required dead-address transfer, not a supply decrement.

Anyone may call `executeBatch()` in its own transaction. It starts a fresh PoolManager unlock; calls while the manager is already unlocked are refused. The caller cannot choose amounts, currencies, price limits, or recipients. It returns `(actualIMDSpent, SWARMLERBurned)` and emits `BatchExecuted(budget, spent, burned, limit, stale)`.

- Budget is `floor(pending / 4)`. If the reference is over 50 blocks old, the budget is halved again, rounding down.
- The swap is exact input, IMD to SWARMLER in the launch pool. A price-limited partial fill is successful. Only **spent** IMD claims are burned for settlement, so every unused unit remains for subsequent batches.
- Output goes directly from PoolManager to the dead address. The batch pays the static LP fee but no hook fee: v4 skips callbacks when the hook itself is the swap sender. The hook explicitly records the batch's price-observation block because those callbacks are skipped.
- `lastBatch()` is updated only when `spent >= ceil(budget / 100)` and `spent != 0`. A meaningful fill starts the 3,600-second cooldown. Dust, zero budget, zero liquidity, or an already reached price bound cannot start or extend it. At exactly 3,600 seconds a new batch is allowed.
- There is no minimum-output or full-fill check. A one-unit budget may all become the pool LP fee; if spent, it meets the specified threshold even when output rounds to zero.

An operation-state guard binds the unlock callback to a pending sweep/batch and prevents reentry. Only the configured manager can invoke it. Claim burns and output transfers settle the hook's swap deltas to zero. There are no token approvals or transferFrom calls in the hook.

## Reference and price limit

At the first state-changing touch in each block (`beforeSwap`, `sweep`, or `executeBatch`), the hook reads the pool's current sqrt price before any trade in that block. This equals its previous block's closing sqrt price. `referencePrice()` stays frozen for the rest of the block. Initialization uses the supplied opening sqrt price because the pool has no prior history. Adding/removing liquidity and donations do not change sqrt price.

`referenceBlock()` is the block of the last pool price observation that supplied that closing value: initialization, an ordinary swap, or a batch swap. `lastPriceBlock()` tracks those observations; `lastTouchedBlock()` identifies the snapshot block. If no swap occurs for many blocks, an unchanged old observation remains old. Sweeps alone cannot refresh its age. A 50-block gap uses the normal budget; a gap of 51 uses **current** sqrt price at execution and half the budget. Within a stale-reference block, that fallback can include earlier same-block trades, exactly as M1 specifies. The next block can use the refreshed closing observation.

M1 defines the reference in **sqrt-price units**. The directional 300 bps bound is therefore:

- SWARMLER is currency0: `floor(reference * 10300 / 10000)`, an increasing PoolManager sqrt-price limit.
- SWARMLER is currency1: `ceil(reference * 10000 / 10300)`, the reciprocal bound for a decreasing sqrt price.

Bounds are clamped to the manager's strict valid sqrt-price endpoints. If spot is already at or past the permitted bound, the batch returns a zero fill instead of submitting a swap with an invalid-direction limit. Applying 3% to sqrt price allows up to 6.09% movement in the corresponding un-squared token price; this is deliberate and is not a 3% spot-price or TWAP constraint. The implementation adds no tick oracle, time-weighted oracle, or other slippage check.

## Validation and operational responsibilities

Run the offline build and full suite at the repository root:

```sh
forge build
forge test
forge fmt --check
```

Mainnet tests explicitly skip without a CLI-selected fork; they never read or modify environment variables. To run against the recorded mainnet state:

```sh
forge test --fork-url https://ethereum-rpc.publicnode.com \
  --fork-block-number 26158413 --no-storage-caching \
  --match-path test/SWARMLERFork.t.sol -vv
```

The fork uses real mainnet PoolManager and IMD code and storage. Foundry funds the local test caller's IMD balance and deploys a fresh SWARMLER/hook; these changes exist only in the fork. Source-built local PoolManager tests run offline and cover both currency address orderings. The stateful conservation test mixes swaps, sweeps, batches, timestamp changes, and skipped blocks; no action reverts in the recorded run. See `docs/SWARMLER-validation.md` for final command results and review details, and `vendor/README.md` for pinned dependency provenance and the previous static-analysis issue's repair.

After launch there are **no owner settings**. Permissionless keepers/users fund their own gas to sweep and execute batches. No keeper reward or guaranteed scheduling is provided. Monitor claims, `lastBatch`, reference age, fills, liquidity, and dead-address transfers; retry partial/dust batches when price and liquidity permit. Routers must settle both returned deltas and allow the extra input cost on exact-output trades.

The manager is the fixed trusted external accounting boundary. IMD is the specified deployed ERC-20, not a generic fee-on-transfer/rebasing asset adapter. Any future failure of that external token or core protocol can still prevent underlying swaps. The prescribed previous-block spot snapshot and stale-price fallback are manipulable market observations, not an independent fair-value oracle; external independent security review remains a release responsibility. No owner can change these tradeoffs after deployment.
