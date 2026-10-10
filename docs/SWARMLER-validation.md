# SWARMLER implementation validation

Recorded locally on 2026-10-10 with Foundry 1.8.5 and Solidity 0.8.26. These are contributor-side results, not independent network attestation or an external audit.

## Commands and results

| Check | Result |
| --- | --- |
| `forge build` and final `forge build --sizes` | Passed with the unchanged root compiler configuration |
| `forge test` | **99 passed, 0 failed, 2 skipped**; the two fork suites explicitly skipped in `setUp` without a selected fork |
| Mainnet fork at block **26,158,413**, command below | **68 passed, 0 failed, 0 skipped** against the deployed PoolManager and IMD |
| `forge fmt --check` | Passed |
| Manifest shape, values, local import closure | Passed a local Python check using the standard library |
| Protected configuration | `foundry.toml` byte-for-byte equal to HEAD; no protected configuration/dependency paths modified |
| Runtime escape-hatch checks | No executable SELFDESTRUCT, DELEGATECALL, or CALLCODE in either launch contract |
| Hook sizes | **7,648 bytes runtime; 8,485 bytes creation bytecode + 64 bytes constructor arguments = 8,549 bytes initcode** |
| Token sizes | 1,360 bytes runtime; 1,468 bytes initcode |

The mainnet run was:

```sh
forge test --fork-url https://ethereum-rpc.publicnode.com \
  --fork-block-number 26158413 --no-storage-caching \
  --match-path test/SWARMLERFork.t.sol -vv
```

The mainnet endpoint returned PoolManager runtime code (24,009 bytes) and IMD's `symbol()` as `IMD`. Fork setup additionally asserts chain id 1 and IMD's 18 decimals. The fork fixtures never replace the deployed manager or IMD code. They provision the test caller's IMD balance, deploy the submitted token and a CREATE2-mined hook, initialize and seed their pool, and exercise actual core swap/unlock/settlement code. Offline verification needs no RPC: it deploys the vendored PoolManager and uses an ordinary local ERC-20 at the specified pair address.

## Coverage

- Every exact-input/exact-output buy and sell in **both** token address orderings, with actual gross pool deltas read from PoolManager's `Swap` event and compared to the returned trader deltas.
- Four price-limited partial-fill cases per ordering, and enormous but representable input/output requests that only fill to the bound.
- 1,000 actual-fill fuzz cases per local ordering; 256 per fork ordering. Tiny fees, zero-unit budgets, one-unit budgets, rounding, and the named error for unrepresentable specified amounts.
- Static pool fee and zero LP override; no specified-side delta; exact permission/address agreement and initialization authentication; wrong pool, repeated initialization, unauthorized callbacks, unrequested unlock callbacks, and nested-unlock rejection.
- Full, partial, dust, empty, out-of-liquidity, and already-beyond-bound batches. Unspent input remains as claims. Dust/zero fills do not start the cooldown; meaningful fills do, including exact 3,600-second eligibility.
- Previous-block closing reference, within-block freeze, age 50 versus 51, stale execution using the first-touch snapshot with half budget, and sweeps that cannot refresh old observations. Atomic pump/batch/dump, repeated zero-fill batches, stale dust-fill retries, and next-block recovery are covered in both currency orderings.
- Anyone-callable sweep, repeated empty sweep, batch output to the dead address, no in-callback transfers/buybacks, and no batch hook fee.
- Fresh one-sided launch liquidity with **zero IMD and zero ETH** in a real local PoolManager before an exact-output buy. The paired input fee is still collected before router settlement.
- Empty-chain construction with no external code, failure before initialization, invalid constructor inputs, wrong permission address, and extreme opening sqrt prices.
- Entire `10^27` supply to the deployer; ordinary transfers, self-transfers, allowance spending/revocation, infinite approval semantics, atomic failure paths, and no common mint/admin/upgrade selectors. 1,000 transfer/allowance fuzz cases.
- Vendor math regression checks: all 256 bit boundaries, 1,000 bit-index fuzz cases, 1,000 full-precision division-identity fuzz cases, rounding, and division/overflow failures.
- All **12 accepted logo checks**, including their 2,000-case fuzz test, remain passing.

The stateful test ran **256 sequences × 64 calls = 16,384 calls, zero reverts**. Actions were swaps, sweeps, batches, and time/block advances. At every step it checked:

1. Every hook/manager transient currency delta is settled, and the global nonzero-delta count is zero.
2. Actual collected IMD fees equal pending IMD claims plus cumulative batch spending.
3. Actual collected token fees equal pending burn claims plus cumulative sweeps.
4. The dead address receives exactly cumulative sweeps plus batch output.
5. Token balances across participants, PoolManager, and the dead address sum to the unchanged supply.

## Stale-reference revision

Finding `4e8a3d228b7768dd024905b5ade47b22350ae64c2ece7b653c9baba1f993a10c` reproduced before editing the hook. The new `test_StaleReferenceRejectsAtomicSandwich` and `test_StaleZeroFillsCannotRatchetPriceWithinBlock` both failed in both currency orderings on the accepted implementation. With SWARMLER as currency0, the sandwich spent **66.607594936708860769 IMD** from the hook and increased the attacker's 600 IMD to **607.232415234335703449 IMD**. Five zero-fill batches moved sqrt price to `91756545168859501751278964702`, past the first block limit `81524501944022545457710779451`.

The sole runtime change removes `anchor = current` from the stale branch. `_touch()` already sampled the current price before any swap in the block; that snapshot now remains the anchor even when its source observation is stale. The half budget, 50-block age boundary, fee accounting, permissions, and cooldown remain unchanged. After repair, the sandwich spends **zero** hook funds and leaves the attacker with **576.938907647395303724 IMD**. Repeated zero fills stop at the first limit. A third regression covers a sweep as first touch, dust partial fills with no cooldown, repeated retries, claim conservation, and recovery with the normal budget after the next block's snapshot. All three tests are inherited by both mainnet fork suites.

Advisory `699795dfd1fec95d04311cafd695f62ed98e64e72a1ccc21d528830516032666` correctly observes that a 1.03 sqrt-price factor permits a 1.0609 spot-price factor. That is the documented M1 interpretation, so no runtime change was made for it. The existing partial-batch test now independently checks the squared price ratio in both currency orderings, within integer rounding. Reviewer verdicts and reproduction details are in `.imd-responses.json`.

## Focused security review

The implemented callbacks authenticate `msg.sender` as the immutable manager and compare the entire pool id to the immutable canonical key. `hookData` is ignored. There is no router allowlist or end-user identity assumption, because neither the fee nor the destination depends on caller identity. Only the callback permissions actually used are enabled; in particular, no before-swap return-delta permission can consume the entire specified amount.

Fees are computed after widening `int128` deltas to `int256`, so the minimum signed 128-bit value can be safely negated. Dividing its magnitude by 100 yields a fee safely representable as a positive `int128`. A budget of `pending / 4` fits in `int256`, and multiplying a `uint160` reference by 10,300 fits in `uint256`. The price limits are clamped before narrowing. These bounds justify the explicit casts reported by Foundry's generic cast lint.

Claim collection performs no token transfer and no external swap. The manager's ERC-6909 mint has no receiver callback. Sweeps clear their pending balance before redeeming. Batch state is calculated from the actual swap result, while the operation state remains active through the entire unlock and final redemption. Only the immutable trusted manager may invoke `unlockCallback`; a callback outside an active operation fails. No arbitrary payer, recipient, target, or external allowance exists in the hook. A failed settlement rolls back the operation and its counters.

The build's generic lints still report signed casts, timestamp comparison, and state/events after external calls. The timestamp comparison is the requested cooldown. External calls are to the authenticated PoolManager, with an active operation guard; its self-initiated batch swap skips hook callbacks. Final output is the fixed, ordinary SWARMLER token. The tests also produce generic `vm.roll` environment-read warnings; the pinned compiler's reference assertions and stale-boundary tests pass. No lint configuration or suppression file was added.

The previous submission's `incorrect-shift` lookup implementation and `incorrect-exp` inverse seed are absent. Their equivalent replacements and tests are documented in `vendor/README.md`. Other upstream algorithms, including FullMath's exact division followed by modular multiplication, remain intact; treating its modular arithmetic as ordinary rounded financial division would be incorrect. Slither/Mythril were not installed or run in this workspace, so no claim is made that their entire output is clean.

This review and the tests do not constitute an independent security audit. Release responsibilities remain the factory's atomic deployment/initialization, source verification, an independent review, and permissionless keeper operation described in `SWARMLER-launch.md`. No transactions were broadcast and no funds were controlled outside local tests/forks.
