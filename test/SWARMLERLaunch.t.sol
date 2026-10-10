// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    HookFixture,
    SWARMLERHook,
    SWARMLER,
    IPoolManager,
    PoolManager,
    PoolKey,
    IHooks,
    SwapParams,
    ModifyLiquidityParams,
    TickMath,
    IERC20Minimal
} from "./support/HookFixture.sol";
import {PoolRouter} from "./support/PoolRouter.sol";
import {MockIMD} from "./support/MockIMD.sol";

/// @notice Empty-chain deployment and a launch pool seeded with SWARMLER only.
contract SWARMLERLaunchTest is HookFixture {
    function setUp() public {
        manager = IPoolManager(address(new PoolManager(address(this))));
        MockIMD model = new MockIMD();
        vm.etch(IMD, address(model).code);
        MockIMD(IMD).mint(address(this), 1e27);
    }

    function test_FreshToken0OnlyPoolCollectsInputClaimsBeforePayment() public {
        _oneSided(true);
    }

    function test_FreshToken1OnlyPoolCollectsInputClaimsBeforePayment() public {
        _oneSided(false);
    }

    function test_ConstructorDoesNotCallExternalContracts() public {
        // These are deliberate no-code test fixtures, never deployment parameters in the manifest.
        address managerWithoutCode = makeAddr("empty-chain manager");
        address tokenWithoutCode = makeAddr("empty-chain token");
        assertEq(managerWithoutCode.code.length, 0);
        assertEq(tokenWithoutCode.code.length, 0);
        SWARMLERHook deployed = _deployHook(IPoolManager(managerWithoutCode), tokenWithoutCode);
        assertEq(address(deployed.poolManager()), managerWithoutCode);
        assertEq(deployed.token(), tokenWithoutCode);
        assertFalse(deployed.initialized());
    }

    function test_OperationsRequireInitialization() public {
        token = _deployToken(true);
        hook = _deployHook(manager, address(token));
        vm.expectRevert(SWARMLERHook.NotInitialized.selector);
        hook.executeBatch();
        vm.expectRevert(SWARMLERHook.NotInitialized.selector);
        hook.sweep();
    }

    function test_NonMinedAddressIsRejected() public {
        SWARMLER launchToken = new SWARMLER();
        bytes32 hash =
            keccak256(abi.encodePacked(type(SWARMLERHook).creationCode, abi.encode(manager, address(launchToken))));
        uint256 salt;
        while (uint160(_predict(bytes32(salt), hash)) & 0x3fff == 0x20c4) ++salt;
        vm.expectRevert(SWARMLERHook.InvalidHookAddress.selector);
        new SWARMLERHook{salt: bytes32(salt)}(manager, address(launchToken));
    }

    function test_InvalidConstructorArgumentsAreRejected() public {
        vm.expectRevert(SWARMLERHook.InvalidConfiguration.selector);
        new SWARMLERHook(IPoolManager(address(0)), IMD);
        vm.expectRevert(SWARMLERHook.InvalidConfiguration.selector);
        new SWARMLERHook(manager, address(0));
        vm.expectRevert(SWARMLERHook.InvalidConfiguration.selector);
        new SWARMLERHook(manager, IMD);
    }

    function test_ExtremeOpeningPricesAreAcceptedAndBatchLimitsClamp() public {
        token = _deployToken(true);
        hook = _deployHook(manager, address(token));
        key = hook.poolKey();
        manager.initialize(key, TickMath.MAX_SQRT_PRICE - 1);
        assertEq(hook.referencePrice(), TickMath.MAX_SQRT_PRICE - 1);
        (uint256 spent,) = hook.executeBatch();
        assertEq(spent, 0);

        token = _deployToken(false);
        hook = _deployHook(manager, address(token));
        key = hook.poolKey();
        manager.initialize(key, TickMath.MIN_SQRT_PRICE);
        assertEq(hook.referencePrice(), TickMath.MIN_SQRT_PRICE);
        (spent,) = hook.executeBatch();
        assertEq(spent, 0);
    }

    function _oneSided(bool tokenFirst) private {
        token = _deployToken(tokenFirst);
        hook = _deployHook(manager, address(token));
        key = hook.poolKey();
        router = new PoolRouter(manager);
        token.approve(address(router), type(uint256).max);
        IERC20Minimal(IMD).approve(address(router), type(uint256).max);
        manager.initialize(key, Q96);
        int24 lower = tokenFirst ? int24(60) : int24(-120);
        int24 upper = tokenFirst ? int24(120) : int24(-60);
        router.liquidity(key, ModifyLiquidityParams(lower, upper, LIQUIDITY, bytes32(0)), FUNDING, FUNDING);
        assertEq(IERC20Minimal(IMD).balanceOf(address(manager)), 0);
        assertEq(address(manager).balance, 0);
        assertGt(token.balanceOf(address(manager)), 0);
        // Exact-output buy charges its extra 1% on IMD input before the router settles any IMD.
        _swap(true, false, 1e20, 0);
        assertGt(hook.pending(), 0);
        assertEq(hook.pendingBurn(), 0);
        _assertSettled();
        (uint256 spent, uint256 burned) = hook.executeBatch();
        assertGt(spent, 0);
        assertGt(burned, 0);
        _assertSettled();
    }
}
