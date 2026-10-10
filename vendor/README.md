# Pinned offline dependencies

These are ordinary source files, with no submodules, install step, remote imports, or link placeholders. The existing Foundry configuration and dependency manifests are unchanged. Relative Solidity imports resolve locally.

| Directory | Upstream | Commit | Contents |
| --- | --- | --- | --- |
| `v4-core/` | https://github.com/Uniswap/v4-core | `46c6834698c48bc4a463a86d8420f4eb1d7f3b75` | Required PoolManager, interfaces, types, and library dependency closure; upstream licenses included |
| `forge-std/` | https://github.com/foundry-rs/forge-std | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` (v1.9.7) | Test support and licenses; not imported by launch contracts |
| `solmate/` | https://github.com/transmissions11/solmate | `4b47a19038b798b4a33d9749d25e570443520647` | `Owned.sol` and license, required by the local test PoolManager; not inherited by launch contracts |

Local adaptations to v4-core are deliberately limited:

1. `ProtocolFees.sol` uses a relative import for the vendored `Owned.sol`.
2. `BitMath.sol` uses constant-shift binary search for the most significant bit, and isolates the lowest set bit before the same search for the least significant bit. This replaces the upstream packed variable-shift lookup tables implicated in the previous submission's `incorrect-shift` report. Zero input still reverts and bit indices are identical. Tests cover every bit boundary and 1,000 fuzz inputs.
3. `FullMath.sol` starts the modular inverse at 1 (correct modulo 2) and uses eight Newton iterations to reach 256 correct bits. This replaces the upstream XOR-based four-bit seed and six iterations implicated in the previous `incorrect-exp` report. XOR in that upstream seed was intentional, not exponentiation; replacing it with `**` would be incorrect. Tests verify the full 512-bit division identity with independent 128-bit limb multiplication, overflow failures, rounding, and 1,000 fuzz inputs.

The actual mainnet PoolManager is not deployed or modified by this project. The fork suite exercises its deployed code directly, in addition to the local source-built manager. Uniswap's license headers remain authoritative for their files. Production SWARMLER contracts have no owner, proxy, or upgrade mechanism.
