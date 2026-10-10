// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    HookFixture,
    SWARMLER,
    SWARMLERHook,
    IPoolManager,
    IERC20Minimal,
    PoolKey,
    PoolId,
    SwapParams,
    ModifyLiquidityParams,
    BalanceDelta,
    TickMath,
    Vm
} from "./support/HookFixture.sol";
import {PoolRouter} from "./support/PoolRouter.sol";
import {MockIMD} from "./support/MockIMD.sol";
import {Test} from "../vendor/forge-std/src/Test.sol";
import {StateLibrary} from "../vendor/v4-core/src/libraries/StateLibrary.sol";

contract SwarmHandler is Test {
    using StateLibrary for IPoolManager;

    struct Fill {
        int128 amount0;
        int128 amount1;
        uint160 price;
        uint128 liquidity;
        int24 tick;
        uint24 fee;
    }
    IPoolManager private immutable manager;
    SWARMLERHook private immutable hook;
    PoolRouter private immutable router;
    PoolKey private key;
    uint256 public pairedCollected;
    uint256 public tokenCollected;
    uint256 public pairedSpent;
    uint256 public bought;
    uint256 public swept;
    uint256 public swaps;
    uint256 public batches;
    uint256 public cooldownReverts;
    uint256 public partialFills;
    uint128 public positionLiquidity = 1e24;
    uint160 public expectedReferencePrice;
    uint256 public expectedReferenceBlock;
    uint256 public expectedTouchedBlock;
    uint256 public expectedLastPriceBlock;
    uint256 public expectedLastBatch;
    bytes32 private constant SWAP_EVENT = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");
    bytes32 private constant BATCH_EVENT = keccak256("BatchExecuted(uint256,uint256,uint256,uint160,bool)");

    constructor(IPoolManager manager_, SWARMLERHook hook_, PoolRouter router_) {
        manager = manager_;
        hook = hook_;
        router = router_;
        key = hook_.poolKey();
        IERC20Minimal(hook_.token()).approve(address(router_), type(uint256).max);
        IERC20Minimal(hook_.PAIRED_CURRENCY()).approve(address(router_), type(uint256).max);
        (expectedReferencePrice,,,) = manager_.getSlot0(key.toId());
        expectedReferenceBlock = vm.getBlockNumber();
        expectedTouchedBlock = vm.getBlockNumber();
        expectedLastPriceBlock = vm.getBlockNumber();
    }

    function swap(bool buy, bool exactInput, uint96 seed, uint8 tickSeed) external {
        uint256 amount = seed % 4 == 0 ? bound(uint256(seed), 1, 1000) : bound(uint256(seed), 1, 1e23);
        bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
        uint160 limit = _swapLimit(zeroForOne, tickSeed);
        if (limit == 0) return;
        _touchModel();
        vm.recordLogs();
        BalanceDelta net =
            router.swap(key, SwapParams(zeroForOne, exactInput ? -int256(amount) : int256(amount), limit), 1e25, "");
        _recordSwap(net, amount, exactInput, zeroForOne);
        expectedLastPriceBlock = vm.getBlockNumber();
        ++swaps;
    }

    function _swapLimit(bool zeroForOne, uint8 tickSeed) private view returns (uint160 limit) {
        (uint160 price, int24 tick,,) = manager.getSlot0(key.toId());
        int24 distance = int24(uint24(tickSeed) + 1);
        int24 target = zeroForOne ? tick - distance : tick + distance;
        if (target <= TickMath.MIN_TICK) target = TickMath.MIN_TICK + 1;
        if (target >= TickMath.MAX_TICK) target = TickMath.MAX_TICK - 1;
        limit = TickMath.getSqrtPriceAtTick(target);
        if (zeroForOne ? limit >= price : limit <= price) return 0;
    }

    function _recordSwap(BalanceDelta net, uint256 amount, bool exactInput, bool zeroForOne) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(manager) && logs[i].topics[0] == SWAP_EVENT) {
                Fill memory raw = abi.decode(logs[i].data, (Fill));
                // Derive collections from trader-versus-pool delta conservation, independently of pending().
                uint256 fee0 = uint256(int256(raw.amount0) - int256(net.amount0()));
                uint256 fee1 = uint256(int256(raw.amount1) - int256(net.amount1()));
                bool unspecified0 = exactInput != zeroForOne;
                uint256 expectedFee = _abs(unspecified0 ? raw.amount0 : raw.amount1) / 100;
                assertEq(fee0, unspecified0 ? expectedFee : 0, "wrong actual-fill currency0 fee");
                assertEq(fee1, unspecified0 ? 0 : expectedFee, "wrong actual-fill currency1 fee");
                assertEq(raw.fee, 12500);
                if (_abs(exactInput == zeroForOne ? raw.amount0 : raw.amount1) < amount) ++partialFills;
                tokenCollected += hook.tokenIsCurrency0() ? fee0 : fee1;
                pairedCollected += hook.tokenIsCurrency0() ? fee1 : fee0;
                found = true;
            }
        }
        assertTrue(found);
    }

    function sweep() external {
        _touchModel();
        uint256 beforeDead = IERC20Minimal(hook.token()).balanceOf(hook.DEAD());
        uint256 burned = hook.sweep();
        assertEq(burned, tokenCollected - swept, "sweep must redeem every collected token fee");
        assertEq(IERC20Minimal(hook.token()).balanceOf(hook.DEAD()) - beforeDead, burned);
        swept += burned;
    }

    function batch() external {
        if (expectedLastBatch != 0 && vm.getBlockTimestamp() - expectedLastBatch < 3600) {
            vm.expectRevert(SWARMLERHook.CooldownActive.selector);
            hook.executeBatch();
            ++cooldownReverts;
            return;
        }
        _touchModel();
        uint256 beforePending = hook.pending();
        uint256 beforeBurn = hook.pendingBurn();
        bool stale = vm.getBlockNumber() - expectedReferenceBlock > 50;
        uint256 budget = beforePending / 4;
        if (stale) budget /= 2;
        (uint160 beforePrice,,,) = manager.getSlot0(key.toId());
        vm.recordLogs();
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertLe(spent, budget, "batch exceeded its fresh/stale budget");
        assertEq(hook.pending(), beforePending - spent);
        assertEq(hook.pendingBurn(), beforeBurn, "batch paid a hook fee");
        _checkBatchLogs(vm.getRecordedLogs(), budget, spent, burned, stale, beforePrice);
        if (spent != 0 && spent * 100 >= budget) expectedLastBatch = vm.getBlockTimestamp();
        pairedSpent += spent;
        bought += burned;
        ++batches;
    }

    function liquidity(uint96 seed, uint8 mode) external {
        // Same real position as the fixture: include fully empty and dust liquidity,
        // then restore enough liquidity to prove subsequent swaps/batches recover.
        uint128 next =
            mode % 3 == 0 ? 0 : mode % 3 == 1 ? uint128(bound(seed, 1, 1000)) : uint128(bound(seed, 1e18, 1e24));
        if (next == positionLiquidity) return;
        router.liquidity(
            key,
            ModifyLiquidityParams(-600, 600, int256(uint256(next)) - int256(uint256(positionLiquidity)), bytes32(0)),
            1e25,
            1e25
        );
        positionLiquidity = next;
    }

    function advance(uint8 blockSeed, uint16 timeSeed) external {
        vm.roll(vm.getBlockNumber() + bound(blockSeed, 0, 70));
        vm.warp(vm.getBlockTimestamp() + bound(timeSeed, 0, 7200));
    }

    function _touchModel() private {
        if (expectedTouchedBlock != vm.getBlockNumber()) {
            (expectedReferencePrice,,,) = manager.getSlot0(key.toId());
            expectedReferenceBlock = expectedLastPriceBlock;
            expectedTouchedBlock = vm.getBlockNumber();
        }
    }

    function _checkBatchLogs(
        Vm.Log[] memory logs,
        uint256 budget,
        uint256 spent,
        uint256 burned,
        bool stale,
        uint160 beforePrice
    ) private {
        bool sawBatch;
        bool sawSwap;
        uint160 limit;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(hook)) {
                assertEq(logs[i].topics[0], BATCH_EVENT, "batch emitted a hook fee");
                assertFalse(sawBatch, "batch emitted twice");
                (
                    uint256 loggedBudget,
                    uint256 loggedSpent,
                    uint256 loggedBurned,
                    uint160 loggedLimit,
                    bool loggedStale
                ) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint160, bool));
                assertEq(loggedBudget, budget);
                assertEq(loggedSpent, spent);
                assertEq(loggedBurned, burned);
                assertEq(loggedStale, stale);
                limit = loggedLimit;
                _checkReferenceLimit(limit);
                sawBatch = true;
            }
            if (logs[i].emitter == address(manager) && logs[i].topics[0] == SWAP_EVENT) {
                assertFalse(sawSwap, "batch performed more than one swap");
                assertEq(logs[i].topics[1], PoolId.unwrap(key.toId()), "batch used a different pool");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(hook), "wrong batch sender");
                (int128 d0, int128 d1,,,, uint24 fee) =
                    abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                assertEq(uint256(-int256(hook.tokenIsCurrency0() ? d1 : d0)), spent);
                assertEq(uint256(int256(hook.tokenIsCurrency0() ? d0 : d1)), burned);
                assertEq(fee, 12500);
                expectedLastPriceBlock = vm.getBlockNumber();
                sawSwap = true;
            }
        }
        assertTrue(sawBatch);
        (uint160 afterPrice,,,) = manager.getSlot0(key.toId());
        bool crossed = hook.tokenIsCurrency0() ? beforePrice >= limit : beforePrice <= limit;
        assertEq(sawSwap, budget != 0 && !crossed, "batch must swap unless empty or already past its bound");
        if (!sawSwap) {
            assertEq(spent + burned, 0);
            assertEq(afterPrice, beforePrice, "skipped batch moved the pool price");
        } else {
            if (hook.tokenIsCurrency0()) {
                assertGe(afterPrice, beforePrice, "batch swapped in the sell direction");
                assertLe(afterPrice, limit, "batch crossed its frozen reference bound");
            } else {
                assertLe(afterPrice, beforePrice, "batch swapped in the sell direction");
                assertGe(afterPrice, limit, "batch crossed its frozen reference bound");
            }
            if (spent < budget) assertEq(afterPrice, limit, "partial fill stopped before its only price limit");
        }
    }

    function _checkReferenceLimit(uint160 limit) private view {
        assertGt(limit, TickMath.MIN_SQRT_PRICE);
        assertLt(limit, TickMath.MAX_SQRT_PRICE);
        // Verify the 300 bps boundary by cross multiplication, including the
        // correct rounding direction. Use the handler's first-touch history,
        // never the hook's getter or the live (possibly manipulated) spot price.
        if (hook.tokenIsCurrency0()) {
            uint256 cap = uint256(expectedReferencePrice) * 10300;
            assertLe(uint256(limit) * 10000, cap, "buyback limit exceeded reference plus 3%");
            if (limit != TickMath.MAX_SQRT_PRICE - 1) assertGt((uint256(limit) + 1) * 10000, cap);
        } else {
            uint256 cap = uint256(expectedReferencePrice) * 10000;
            assertGe(uint256(limit) * 10300, cap, "reciprocal buyback limit exceeded reference plus 3%");
            if (limit != TickMath.MIN_SQRT_PRICE + 1) assertLt((uint256(limit) - 1) * 10300, cap);
        }
    }

    function _abs(int128 amount) private pure returns (uint256) {
        return uint256(amount < 0 ? -int256(amount) : int256(amount));
    }
}

contract SWARMLERInvariantTest is HookFixture {
    SwarmHandler internal handler;

    function setUp() public virtual {
        _setUpInvariant(true);
    }

    function _setUpInvariant(bool tokenFirst) internal {
        _setUp(tokenFirst, false);
        handler = new SwarmHandler(manager, hook, router);
        token.transfer(address(handler), 2e26);
        MockIMD(IMD).mint(address(handler), 1e29);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.swap.selector;
        selectors[1] = handler.sweep.selector;
        selectors[2] = handler.batch.selector;
        selectors[3] = handler.advance.selector;
        selectors[4] = handler.liquidity.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ClaimsFeesBurnsAndSupplyAreConserved() public view virtual {
        _assertSettled();
        assertEq(handler.pairedCollected(), hook.pending() + handler.pairedSpent());
        assertEq(handler.tokenCollected(), hook.pendingBurn() + handler.swept());
        assertEq(token.balanceOf(DEAD), handler.bought() + handler.swept());
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(address(handler)) + token.balanceOf(address(manager))
                + token.balanceOf(DEAD),
            token.totalSupply()
        );
        assertEq(token.totalSupply(), 1e27);
        assertEq(hook.referencePrice(), handler.expectedReferencePrice(), "wrong previous-block price");
        assertEq(hook.referenceBlock(), handler.expectedReferenceBlock(), "wrong reference age");
        assertEq(hook.lastTouchedBlock(), handler.expectedTouchedBlock());
        assertEq(hook.lastPriceBlock(), handler.expectedLastPriceBlock());
        assertEq(hook.lastBatch(), handler.expectedLastBatch(), "dust/zero fill changed the cooldown");
        assertGe(IERC20Minimal(IMD).balanceOf(address(manager)), hook.pending());
        assertGe(token.balanceOf(address(manager)), hook.pendingBurn());
        assertEq(
            IERC20Minimal(IMD).balanceOf(address(this)) + IERC20Minimal(IMD).balanceOf(address(handler))
                + IERC20Minimal(IMD).balanceOf(address(manager)),
            MockIMD(IMD).totalSupply(),
            "paired currency escaped the tracked participants"
        );
    }
}

contract SWARMLERInvariantToken1Test is SWARMLERInvariantTest {
    function setUp() public override {
        _setUpInvariant(false);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ClaimsFeesBurnsAndSupplyAreConserved() public view override {
        super.invariant_ClaimsFeesBurnsAndSupplyAreConserved();
    }
}
