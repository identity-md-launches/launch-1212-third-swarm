// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    HookFixture,
    SWARMLERHook,
    SWARMLER,
    IHooks,
    IERC20Minimal,
    SwapParams,
    BalanceDelta,
    TickMath,
    Hooks
} from "./HookFixture.sol";
import {CustomRevert} from "../../vendor/v4-core/src/libraries/CustomRevert.sol";
import {CurrencyLibrary} from "../../vendor/v4-core/src/types/Currency.sol";

/// @dev Shared by both local address orderings and the opt-in mainnet suites.
abstract contract HookFailureChecks is HookFixture {
    /// A larger unfilled request must not change either the trader's debit or the fee.
    function _unfilledRequestCannotIncreaseFee(bool buy, bool exactInput, uint256 extra) internal {
        extra = bound(extra, 1, uint256(type(int256).max) / 2);
        bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
        uint160 limit = TickMath.getSqrtPriceAtTick(zeroForOne ? int24(-30) : int24(30));
        uint256 snapshot = vm.snapshotState();
        (BalanceDelta firstNet, BalanceDelta firstRaw) = _swap(buy, exactInput, 1e25, limit);
        uint256 specifiedFill = _abs(exactInput == zeroForOne ? firstRaw.amount0() : firstRaw.amount1());
        assertGt(specifiedFill, 0);
        assertLt(specifiedFill, 1e25);
        assertEq(_price(), limit);
        bytes32 firstState = _economicState();

        assertTrue(vm.revertToStateAndDelete(snapshot));
        (BalanceDelta largerNet, BalanceDelta largerRaw) = _swap(buy, exactInput, 1e25 + extra, limit);
        assertEq(BalanceDelta.unwrap(largerRaw), BalanceDelta.unwrap(firstRaw), "unfilled amount changed pool fill");
        assertEq(BalanceDelta.unwrap(largerNet), BalanceDelta.unwrap(firstNet), "unfilled amount changed trader cost");
        assertEq(_economicState(), firstState, "unfilled amount changed fees or balances");
    }

    function test_RepresentableRequestBoundaryThroughManager() public {
        uint256 max = uint256(type(int256).max);
        // Solve x + floor(x / 100) <= int256.max without overflowing the calculation.
        uint256 remainder = max % 101;
        uint256 largest = (max / 101) * 100 + (remainder < 100 ? remainder : 99);
        for (uint256 mode; mode < 4; ++mode) {
            bool buy = mode < 2;
            bool exactInput = mode % 2 == 0;
            bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
            uint160 limit = TickMath.getSqrtPriceAtTick(zeroForOne ? int24(-30) : int24(30));
            uint256 snapshot = vm.snapshotState();
            int256 invalid = exactInput ? -int256(largest + 1) : int256(largest + 1);
            vm.expectRevert(
                abi.encodeWithSelector(
                    CustomRevert.WrappedError.selector,
                    address(hook),
                    IHooks.beforeSwap.selector,
                    abi.encodeWithSelector(SWARMLERHook.UnrepresentableFee.selector),
                    abi.encodeWithSelector(Hooks.HookCallFailed.selector)
                )
            );
            router.swap(key, SwapParams(zeroForOne, invalid, limit), FUNDING, "");
            _swap(buy, exactInput, largest, limit);
            assertEq(_price(), limit, "largest accepted request should partially fill");
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function test_AllSwapModesWithNoLiquidityChargeNothing() public {
        _liquidity(-LIQUIDITY);
        for (uint256 mode; mode < 4; ++mode) {
            bool buy = mode < 2;
            bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
            uint160 limit = TickMath.getSqrtPriceAtTick(zeroForOne ? int24(-30) : int24(30));
            uint256 snapshot = vm.snapshotState();
            (BalanceDelta net, BalanceDelta raw) = _swap(buy, mode % 2 == 0, 1e25, limit);
            assertEq(BalanceDelta.unwrap(raw), 0);
            assertEq(BalanceDelta.unwrap(net), 0);
            assertEq(hook.pending(), 0);
            assertEq(hook.pendingBurn(), 0);
            assertEq(token.balanceOf(DEAD), 0);
            assertTrue(vm.revertToStateAndDelete(snapshot));
        }
    }

    function test_UnpaidSwapRollsBackFeesPriceAndReference() public {
        _pairFees();
        _swap(true, true, 1e20, 0);
        vm.roll(vm.getBlockNumber() + 1);
        bytes32 beforeState = _economicState();
        // An exact-output sell owes SWARMLER (including the hook fee). The router
        // deliberately supplies none, so failure happens after afterSwap has run.
        bool zeroForOne = hook.tokenIsCurrency0();
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        (bool success, bytes memory reason) =
            address(router).call(abi.encodeCall(router.swap, (key, SwapParams(zeroForOne, 1e20, limit), 0, bytes(""))));
        assertFalse(success, "unfunded swap succeeded");
        _assertInsufficientBalance(reason);
        assertEq(_economicState(), beforeState, "unpaid swap left accounting behind");
        _assertSettled();
        _swap(false, false, 1e20, limit);
    }

    function test_FailedSweepPreservesClaimsAndCanBeRetried() public {
        _pairFees();
        _swap(true, true, 1e21, 0);
        vm.roll(vm.getBlockNumber() + 1);
        bytes32 beforeState = _economicState();
        uint256 owed = hook.pendingBurn();
        _refuseBurnTransfer();
        _expectBurnTransferFailure();
        hook.sweep();
        vm.clearMockedCalls();
        assertEq(_economicState(), beforeState, "failed redemption destroyed claims");
        _assertSettled();
        assertEq(hook.sweep(), owed, "operation lock was not rolled back");
        assertEq(token.balanceOf(DEAD), owed);
        _assertSettled();
    }

    function test_FailedBatchPreservesBudgetAndCooldownAndCanBeRetried() public {
        _pairFees();
        vm.roll(vm.getBlockNumber() + 1);
        bytes32 beforeState = _economicState();
        uint256 budget = hook.pending() / 4;
        _refuseBurnTransfer();
        _expectBurnTransferFailure();
        hook.executeBatch();
        vm.clearMockedCalls();
        assertEq(_economicState(), beforeState, "failed batch spent claims or started cooldown");
        _assertSettled();
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertEq(spent, budget);
        assertGt(burned, 0);
        assertEq(token.balanceOf(DEAD), burned);
        _assertSettled();
    }

    function test_DustAfterSuccessfulBatchDoesNotRestartCooldown() public {
        _pairFees();
        hook.executeBatch();
        uint256 previous = hook.lastBatch();
        vm.warp(previous + 3600);
        vm.roll(vm.getBlockNumber() + 1);
        _liquidity(-LIQUIDITY);
        _liquidity(1000);
        uint256 budget = hook.pending() / 4;
        (uint256 dust,) = hook.executeBatch();
        assertGt(dust, 0);
        assertLt(dust * 100, budget);
        assertEq(hook.lastBatch(), previous);
        (uint256 retry,) = hook.executeBatch();
        assertEq(retry, 0);
        assertEq(hook.lastBatch(), previous);
        _liquidity(LIQUIDITY);
        vm.roll(vm.getBlockNumber() + 1);
        (uint256 recovered,) = hook.executeBatch();
        assertGt(recovered, 0);
        assertEq(hook.lastBatch(), vm.getBlockTimestamp());
        _assertSettled();
    }

    function test_CooldownRevertDoesNotLockSweeps() public {
        _pairFees();
        hook.executeBatch();
        _swap(true, true, 1e21, 0);
        uint256 owed = hook.pendingBurn();
        bytes32 beforeState = _economicState();
        vm.expectRevert(SWARMLERHook.CooldownActive.selector);
        hook.executeBatch();
        assertEq(_economicState(), beforeState);
        vm.prank(makeAddr("unprivileged sweeper"));
        assertEq(hook.sweep(), owed);
        _assertSettled();
    }

    function test_BatchClosingPriceBecomesNextBlocksReference() public {
        _pairFees();
        uint160 previousClose = _price();
        vm.roll(vm.getBlockNumber() + 1);
        hook.executeBatch();
        assertEq(hook.referencePrice(), previousClose);
        uint160 batchClose = _price();
        assertTrue(batchClose != previousClose);
        uint256 batchBlock = vm.getBlockNumber();
        vm.roll(batchBlock + 1);
        // A sweep can be the first touch; a later trade must not refresh the anchor.
        hook.sweep();
        assertEq(hook.referencePrice(), batchClose);
        assertEq(hook.referenceBlock(), batchBlock);
        _swap(false, true, 1e21, 0);
        assertEq(hook.referencePrice(), batchClose);
    }

    function _refuseBurnTransfer() private {
        // Fault injection at the external transfer only: the real PoolManager still
        // executes the complete claim redemption / swap before this fails.
        vm.mockCallRevert(address(token), abi.encodeWithSelector(IERC20Minimal.transfer.selector, DEAD), hex"decafbad");
    }

    function _assertInsufficientBalance(bytes memory reason) private view {
        assertEq(bytes4(reason), CustomRevert.WrappedError.selector);
        bytes memory arguments = new bytes(reason.length - 4);
        for (uint256 i; i < arguments.length; ++i) {
            arguments[i] = reason[i + 4];
        }
        // Decode dynamic bytes instead of comparing their unused ABI padding: v4's
        // assembly revert wrapper may leave nonzero bytes outside the reason length.
        (address target, bytes4 selector, bytes memory inner, bytes memory details) =
            abi.decode(arguments, (address, bytes4, bytes, bytes));
        assertEq(target, address(token));
        assertEq(selector, IERC20Minimal.transfer.selector);
        assertEq(inner, abi.encodeWithSelector(SWARMLER.InsufficientBalance.selector));
        assertEq(details, abi.encodeWithSelector(CurrencyLibrary.ERC20TransferFailed.selector));
    }

    function _expectBurnTransferFailure() private {
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(token),
                IERC20Minimal.transfer.selector,
                hex"decafbad",
                abi.encodeWithSelector(CurrencyLibrary.ERC20TransferFailed.selector)
            )
        );
    }

    function _economicState() private view returns (bytes32) {
        bytes32 hookState = keccak256(
            abi.encode(
                hook.pending(),
                hook.pendingBurn(),
                hook.lastBatch(),
                hook.referencePrice(),
                hook.referenceBlock(),
                hook.lastTouchedBlock(),
                hook.lastPriceBlock(),
                _price()
            )
        );
        bytes32 custody = keccak256(
            abi.encode(
                token.balanceOf(address(manager)),
                token.balanceOf(address(this)),
                token.balanceOf(DEAD),
                IERC20Minimal(IMD).balanceOf(address(manager)),
                IERC20Minimal(IMD).balanceOf(address(this)),
                manager.balanceOf(address(hook), uint160(IMD)),
                manager.balanceOf(address(hook), uint160(address(token)))
            )
        );
        return keccak256(abi.encode(hookState, custody));
    }
}
