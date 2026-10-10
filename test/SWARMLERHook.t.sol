// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    HookFixture,
    SWARMLERHook,
    SWARMLER,
    IPoolManager,
    IHooks,
    Hooks,
    SwapParams,
    ModifyLiquidityParams,
    PoolKey,
    PoolId,
    Currency,
    BalanceDelta,
    BeforeSwapDelta,
    TickMath,
    IERC20Minimal,
    Vm
} from "./support/HookFixture.sol";
import {IUnlockCallback} from "../vendor/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {HookFailureChecks} from "./support/HookFailureChecks.sol";

contract SWARMLERHookTest is HookFailureChecks, IUnlockCallback {
    function setUp() public virtual {
        _setUp(true, false);
    }

    function test_ExactInputBuy() public {
        _checkFee(true, true, 1e21, 0);
    }

    function test_ExactInputSell() public {
        _checkFee(false, true, 1e21, 0);
    }

    function test_ExactOutputBuy() public {
        _checkFee(true, false, 1e21, 0);
    }

    function test_ExactOutputSell() public {
        _checkFee(false, false, 1e21, 0);
    }

    function test_ExactInputPartialBuy() public {
        _partial(true, true);
    }

    function test_ExactInputPartialSell() public {
        _partial(false, true);
    }

    function test_ExactOutputPartialBuy() public {
        _partial(true, false);
    }

    function test_ExactOutputPartialSell() public {
        _partial(false, false);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ActualFillFees(bool buy, bool exactInput, uint96 amountSeed, uint8 ticks) public virtual {
        uint256 amount = bound(uint256(amountSeed), 1, 1e25);
        bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
        int24 distance = int24(uint24(ticks) + 1);
        uint160 limit = TickMath.getSqrtPriceAtTick(zeroForOne ? -distance : distance);
        _checkFee(buy, exactInput, amount, limit);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_UnfilledRequestCannotIncreaseFee(bool buy, bool exactInput, uint256 extra) public virtual {
        _unfilledRequestCannotIncreaseFee(buy, exactInput, extra);
    }

    function test_FeesAreRoundedDownForTinySwaps() public {
        _checkFee(true, true, 10, 0);
        _checkFee(false, false, 10, 0);
        assertEq(hook.pendingBurn(), 0);
    }

    function test_SweepAnyoneBurnsOnlyTokenClaims() public {
        _pairFees();
        _swap(true, true, 1e21, 0);
        uint256 burn = hook.pendingBurn();
        uint256 paired = hook.pending();
        assertGt(burn, 0);
        uint256 supply = token.totalSupply();
        vm.prank(address(0xBEEF));
        assertEq(hook.sweep(), burn);
        assertEq(token.balanceOf(DEAD), burn);
        assertEq(hook.pending(), paired);
        assertEq(hook.pendingBurn(), 0);
        assertEq(hook.sweep(), 0);
        assertEq(token.totalSupply(), supply, "dead-address transfers preserve totalSupply");
        _assertSettled();
    }

    function test_EmptyBatchDoesNotStartCooldown() public {
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertEq(spent, 0);
        assertEq(burned, 0);
        assertEq(hook.lastBatch(), 0);
        _pairFees();
        (spent, burned) = hook.executeBatch();
        assertGt(spent, 0);
        assertGt(burned, 0);
    }

    function test_OneUnitBudgetCanStartCooldownWithoutMinimumOutput() public {
        _swap(false, true, 500, 0);
        assertEq(hook.pending(), 4);
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertEq(spent, 1);
        assertEq(burned, 0, "one unit may all go to the LP fee");
        assertEq(hook.lastBatch(), block.timestamp);
        assertEq(hook.pending(), 3);
        _assertSettled();
    }

    function test_SubUnitBudgetAccumulatesWithoutCooldown() public {
        _swap(false, true, 300, 0);
        assertLt(hook.pending(), 4);
        (uint256 spent,) = hook.executeBatch();
        assertEq(spent, 0);
        assertEq(hook.lastBatch(), 0);
        _swap(false, true, 1e18, 0);
        (spent,) = hook.executeBatch();
        assertGt(spent, 0);
    }

    function test_BatchBudgetClaimsAndNoHookFee() public {
        uint256 fees = _pairFees();
        uint256 pairedBefore = IERC20Minimal(IMD).balanceOf(address(manager));
        uint256 tokenBefore = token.balanceOf(address(manager));
        uint256 burnPending = hook.pendingBurn();
        vm.prank(address(0xBEEF));
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertEq(spent, fees / 4);
        assertGt(burned, 0);
        assertEq(hook.pending(), fees - spent);
        assertEq(hook.pendingBurn(), burnPending, "batch incorrectly charged a hook fee");
        assertEq(token.balanceOf(DEAD), burned);
        assertEq(IERC20Minimal(IMD).balanceOf(address(manager)), pairedBefore, "claims settle input internally");
        assertEq(token.balanceOf(address(manager)), tokenBefore - burned);
        assertEq(hook.lastBatch(), block.timestamp);
        _assertSettled();
    }

    function test_CooldownBoundaryAndSwapsStayLive() public {
        _pairFees();
        hook.executeBatch();
        uint256 started = hook.lastBatch();
        vm.expectRevert(SWARMLERHook.CooldownActive.selector);
        hook.executeBatch();
        _checkFee(true, false, 1e19, 0);
        _checkFee(false, true, 1e19, 0);
        vm.warp(started + 3599);
        vm.expectRevert(SWARMLERHook.CooldownActive.selector);
        hook.executeBatch();
        vm.warp(started + 3600);
        (uint256 spent,) = hook.executeBatch();
        assertGt(spent, 0);
        assertEq(hook.lastBatch(), started + 3600);
    }

    function test_ReferenceTracksPreviousBlockAndFreezesWithinBlock() public {
        vm.roll(block.number + 1);
        uint256 firstBlock = block.number;
        _swap(false, true, 1e21, 0);
        assertEq(hook.referencePrice(), Q96);
        _swap(false, true, 2e21, 0);
        assertEq(hook.referencePrice(), Q96);
        uint160 closingPrice = _price();
        assertTrue(closingPrice != Q96);
        vm.roll(firstBlock + 1);
        _swap(true, true, 1e20, 0);
        assertEq(hook.referencePrice(), closingPrice);
        assertEq(hook.referenceBlock(), firstBlock);
        hook.sweep();
        assertEq(hook.referencePrice(), closingPrice);
    }

    function test_FiftyBlockReferenceUsesFullBudget() public {
        uint256 fees = _pairFees();
        vm.roll(block.number + 50);
        (uint256 spent,) = hook.executeBatch();
        assertEq(spent, fees / 4);
    }

    function test_StaleReferenceUsesCurrentPriceAndHalfBudget() public {
        uint256 fees = _pairFees();
        vm.roll(block.number + 51);
        _swap(true, true, 1e21, 0);
        uint160 current = _price();
        assertTrue(hook.referencePrice() != current);
        vm.recordLogs();
        (uint256 spent,) = hook.executeBatch();
        assertEq(spent, fees / 8);
        _assertBatchLog(fees / 8, _limit(current), true);
    }

    function test_SweepCannotRefreshAnOldPrice() public {
        uint256 fees = _pairFees();
        uint256 lastPrice = hook.lastPriceBlock();
        vm.roll(lastPrice + 30);
        hook.sweep();
        vm.roll(lastPrice + 51);
        hook.sweep();
        assertEq(hook.referenceBlock(), lastPrice);
        (uint256 spent,) = hook.executeBatch();
        assertEq(spent, fees / 8);
    }

    function test_PartialBatchRetainsRemainderAndStartsCooldown() public {
        uint256 fees = _pairFees();
        _liquidity(-LIQUIDITY);
        _liquidity(1e19);
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertGt(spent, (fees / 4 + 99) / 100);
        assertLt(spent, fees / 4);
        assertGt(burned, 0);
        assertEq(hook.pending(), fees - spent);
        assertEq(_price(), _limit(Q96));
        assertEq(hook.lastBatch(), block.timestamp);
        _assertSettled();
    }

    function test_DustPartialFillNeverBlocksNextBatch() public {
        uint256 fees = _pairFees();
        _liquidity(-LIQUIDITY);
        _liquidity(1000);
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertGt(spent, 0);
        assertLt(spent, (fees / 4 + 99) / 100);
        assertGt(burned, 0);
        assertEq(hook.lastBatch(), 0);
        assertEq(hook.pending(), fees - spent);
        // Bound already reached: retry is a harmless zero fill and leaves cooldown untouched.
        (uint256 retry,) = hook.executeBatch();
        assertEq(retry, 0);
        assertEq(hook.lastBatch(), 0);
        vm.roll(block.number + 1);
        _liquidity(LIQUIDITY);
        (uint256 recovered,) = hook.executeBatch();
        assertGt(recovered, 0);
        assertEq(hook.lastBatch(), block.timestamp);
        _assertSettled();
    }

    function test_NoLiquidityKeepsAllClaimsAndNoCooldown() public {
        uint256 fees = _pairFees();
        _liquidity(-LIQUIDITY);
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertEq(spent, 0);
        assertEq(burned, 0);
        assertEq(hook.pending(), fees);
        assertEq(hook.lastBatch(), 0);
        _assertSettled();
    }

    function test_PriceBeyondLimitSkipsBatchButAllowsSwaps() public {
        uint256 fees = _pairFees();
        bool zeroForOne = !hook.tokenIsCurrency0();
        uint160 beyond = TickMath.getSqrtPriceAtTick(zeroForOne ? int24(-599) : int24(599));
        _swap(true, true, 1e25, beyond);
        (uint256 spent,) = hook.executeBatch();
        assertEq(spent, 0);
        assertEq(hook.pending(), fees);
        assertEq(hook.lastBatch(), 0);
        _checkFee(false, true, 1e20, 0);
    }

    function test_CallbacksRejectUnauthenticatedCalls() public {
        vm.expectRevert(SWARMLERHook.OnlyPoolManager.selector);
        hook.beforeInitialize(address(this), key, Q96);
        SwapParams memory params = SwapParams(true, -1 ether, Q96 / 2);
        vm.expectRevert(SWARMLERHook.OnlyPoolManager.selector);
        hook.beforeSwap(address(this), key, params, "");
        vm.expectRevert(SWARMLERHook.OnlyPoolManager.selector);
        hook.afterSwap(address(this), key, params, BalanceDelta.wrap(0), "");
        vm.expectRevert(SWARMLERHook.OnlyPoolManager.selector);
        hook.unlockCallback("");
        vm.prank(address(manager));
        vm.expectRevert(SWARMLERHook.UnexpectedUnlock.selector);
        hook.unlockCallback("");
    }

    function test_RejectWrongPoolAndReinitialization() public {
        PoolKey memory wrong = key;
        wrong.fee = 3000;
        vm.expectRevert();
        manager.initialize(wrong, Q96);
        vm.prank(address(manager));
        vm.expectRevert(SWARMLERHook.InvalidPool.selector);
        hook.beforeSwap(address(this), wrong, SwapParams(true, -1 ether, Q96 / 2), "");
        vm.prank(address(manager));
        vm.expectRevert(SWARMLERHook.AlreadyInitialized.selector);
        hook.beforeInitialize(address(this), key, Q96);
    }

    function test_PermissionBitsAndSize() public view {
        Hooks.Permissions memory p = hook.getHookPermissions();
        assertTrue(p.beforeInitialize && p.beforeSwap && p.afterSwap && p.afterSwapReturnDelta);
        assertFalse(p.afterInitialize || p.beforeAddLiquidity || p.afterAddLiquidity || p.beforeRemoveLiquidity);
        assertFalse(p.afterRemoveLiquidity || p.beforeDonate || p.afterDonate || p.beforeSwapReturnDelta);
        assertFalse(p.afterAddLiquidityReturnDelta || p.afterRemoveLiquidityReturnDelta);
        assertEq(uint160(address(hook)) & 0x3fff, 0x20c4);
        assertLe(type(SWARMLERHook).creationCode.length + 64, 49152);
        assertLe(address(hook).code.length, 24576);
        _noEscapeHatch(address(hook).code);
        _noEscapeHatch(address(token).code);
    }

    function test_UnrepresentableRequestFailsWithNamedError() public {
        vm.prank(address(manager));
        vm.expectRevert(SWARMLERHook.UnrepresentableFee.selector);
        hook.beforeSwap(address(this), key, SwapParams(true, type(int256).max, Q96 / 2), "");
        vm.prank(address(manager));
        vm.expectRevert(SWARMLERHook.UnrepresentableFee.selector);
        hook.beforeSwap(address(this), key, SwapParams(true, type(int256).min, Q96 / 2), "");
        // An enormous but representable specified request with a price limit remains a real partial fill.
        _checkFee(true, false, uint256(type(int256).max) / 2, _limit(Q96));
    }

    function test_EnormousExactInputOnlyChargesActualPartialFill() public {
        uint160 limit = _limit(Q96);
        _checkFee(true, true, uint256(type(int256).max) / 2, limit);
        assertEq(_price(), limit);
    }

    function test_BeforeSwapNeverChangesSpecifiedAmountOrLPFee() public {
        vm.prank(address(manager));
        (bytes4 selector, BeforeSwapDelta change, uint24 lpFee) =
            hook.beforeSwap(address(this), key, SwapParams(true, -1 ether, Q96 / 2), hex"ffffffff");
        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(BeforeSwapDelta.unwrap(change), 0);
        assertEq(lpFee, 0);
    }

    function test_CannotStartBatchOrSweepInsideAnotherUnlock() public {
        _pairFees();
        bytes memory result = manager.unlock("");
        assertEq(abi.decode(result, (bool)), true);
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == address(manager));
        vm.expectRevert(SWARMLERHook.ManagerAlreadyUnlocked.selector);
        hook.executeBatch();
        vm.expectRevert(SWARMLERHook.ManagerAlreadyUnlocked.selector);
        hook.sweep();
        return abi.encode(true);
    }

    function _partial(bool buy, bool exactInput) internal {
        bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
        uint160 limit = TickMath.getSqrtPriceAtTick(zeroForOne ? int24(-30) : int24(30));
        (BalanceDelta raw,) = _checkFee(buy, exactInput, 1e25, limit);
        uint256 filled = _abs((exactInput == zeroForOne) ? raw.amount0() : raw.amount1());
        assertLt(filled, 1e25 / 100, "partial-fill case unexpectedly filled in full");
        assertEq(_price(), limit);
    }

    function _checkFee(bool buy, bool exactInput, uint256 amount, uint160 limit)
        internal
        returns (BalanceDelta raw, uint256 fee)
    {
        uint256 pairBefore = hook.pending();
        uint256 burnBefore = hook.pendingBurn();
        uint256 deadBefore = token.balanceOf(DEAD);
        BalanceDelta net;
        (net, raw) = _swap(buy, exactInput, amount, limit);
        bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
        bool unspecified0 = exactInput != zeroForOne;
        int128 actual = unspecified0 ? raw.amount0() : raw.amount1();
        fee = _abs(actual) / 100;
        assertEq(int256(unspecified0 ? net.amount0() : net.amount1()), int256(actual) - int256(fee));
        assertEq(unspecified0 ? net.amount1() : net.amount0(), unspecified0 ? raw.amount1() : raw.amount0());
        bool launchFee = buy == exactInput;
        assertEq(hook.pending() - pairBefore, launchFee ? 0 : fee);
        assertEq(hook.pendingBurn() - burnBefore, launchFee ? fee : 0);
        assertEq(token.balanceOf(DEAD), deadBefore, "callbacks must not burn or buy back");
    }

    function _limit(uint160 price) internal view returns (uint160) {
        return hook.tokenIsCurrency0()
            ? uint160(uint256(price) * 10300 / 10000)
            : uint160((uint256(price) * 10000 + 10299) / 10300);
    }

    function _assertBatchLog(uint256 budget, uint160 limit, bool stale) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventId = keccak256("BatchExecuted(uint256,uint256,uint256,uint160,bool)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(hook) && logs[i].topics[0] == eventId) {
                (uint256 gotBudget,,, uint160 gotLimit, bool gotStale) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint160, bool));
                assertEq(gotBudget, budget);
                assertEq(gotLimit, limit);
                assertEq(gotStale, stale);
                found = true;
            }
        }
        assertTrue(found, "batch event missing");
    }

    function _noEscapeHatch(bytes memory code) internal pure {
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xff && op != 0xf4 && op != 0xf2, "forbidden runtime opcode");
        }
    }
}

/// @dev Run the entire economic suite in the opposite address ordering as well.
contract SWARMLERHookToken1Test is SWARMLERHookTest {
    function setUp() public override {
        _setUp(false, false);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ActualFillFees(bool buy, bool exactInput, uint96 amountSeed, uint8 ticks) public override {
        super.testFuzz_ActualFillFees(buy, exactInput, amountSeed, ticks);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_UnfilledRequestCannotIncreaseFee(bool buy, bool exactInput, uint256 extra) public override {
        super.testFuzz_UnfilledRequestCannotIncreaseFee(buy, exactInput, extra);
    }
}
