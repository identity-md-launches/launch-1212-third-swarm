// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    HookFixture,
    SWARMLER,
    SWARMLERHook,
    IPoolManager,
    IERC20Minimal,
    PoolKey,
    SwapParams,
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

    constructor(IPoolManager manager_, SWARMLERHook hook_, PoolRouter router_) {
        manager = manager_;
        hook = hook_;
        router = router_;
        key = hook_.poolKey();
        IERC20Minimal(hook_.token()).approve(address(router_), type(uint256).max);
        IERC20Minimal(hook_.PAIRED_CURRENCY()).approve(address(router_), type(uint256).max);
    }

    function swap(bool buy, bool exactInput, uint96 seed) external {
        uint256 amount = bound(uint256(seed), 1, 1e21);
        bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        (uint160 price,,,) = manager.getSlot0(key.toId());
        if (price == limit) return;
        vm.recordLogs();
        BalanceDelta net =
            router.swap(key, SwapParams(zeroForOne, exactInput ? -int256(amount) : int256(amount), limit), 1e25, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 swapEvent = keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(manager) && logs[i].topics[0] == swapEvent) {
                (int128 raw0, int128 raw1,,,,) =
                    abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                // Derive collections from trader-versus-pool delta conservation, independently of pending().
                uint256 fee0 = uint256(int256(raw0) - int256(net.amount0()));
                uint256 fee1 = uint256(int256(raw1) - int256(net.amount1()));
                assertTrue(fee0 == 0 || fee1 == 0, "charged both currencies");
                tokenCollected += hook.tokenIsCurrency0() ? fee0 : fee1;
                pairedCollected += hook.tokenIsCurrency0() ? fee1 : fee0;
                found = true;
            }
        }
        assertTrue(found);
        ++swaps;
    }

    function sweep() external {
        swept += hook.sweep();
    }

    function batch() external {
        uint256 last = hook.lastBatch();
        if (last != 0 && block.timestamp - last < 3600) return;
        uint256 beforePending = hook.pending();
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertLe(spent, beforePending / 4);
        pairedSpent += spent;
        bought += burned;
        ++batches;
    }

    function advance(uint8 blockSeed, uint16 timeSeed) external {
        vm.roll(block.number + bound(blockSeed, 1, 70));
        vm.warp(block.timestamp + bound(timeSeed, 0, 7200));
    }
}

contract SWARMLERInvariantTest is HookFixture {
    SwarmHandler private handler;

    function setUp() public {
        _setUp(true, false);
        handler = new SwarmHandler(manager, hook, router);
        token.transfer(address(handler), 2e26);
        MockIMD(IMD).mint(address(handler), 1e29);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.swap.selector;
        selectors[1] = handler.sweep.selector;
        selectors[2] = handler.batch.selector;
        selectors[3] = handler.advance.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ClaimsFeesBurnsAndSupplyAreConserved() public view {
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
    }
}
