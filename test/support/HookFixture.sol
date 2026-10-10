// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "../../vendor/forge-std/src/Test.sol";
import {SWARMLER} from "../../src/SWARMLER.sol";
import {SWARMLERHook} from "../../src/SWARMLERHook.sol";
import {PoolManager} from "../../vendor/v4-core/src/PoolManager.sol";
import {IPoolManager} from "../../vendor/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "../../vendor/v4-core/src/interfaces/IHooks.sol";
import {IERC20Minimal} from "../../vendor/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Hooks} from "../../vendor/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "../../vendor/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "../../vendor/v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "../../vendor/v4-core/src/libraries/TickMath.sol";
import {Currency} from "../../vendor/v4-core/src/types/Currency.sol";
import {PoolKey} from "../../vendor/v4-core/src/types/PoolKey.sol";
import {PoolId} from "../../vendor/v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "../../vendor/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "../../vendor/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "../../vendor/v4-core/src/types/BeforeSwapDelta.sol";
import {MockIMD} from "./MockIMD.sol";
import {PoolRouter} from "./PoolRouter.sol";

abstract contract HookFixture is Test {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    address internal constant IMD = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address internal constant MAINNET_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    uint160 internal constant Q96 = 79228162514264337593543950336;
    uint256 internal constant FUNDING = 1e26;
    int256 internal constant LIQUIDITY = 1e24;
    bytes32 internal constant SWAP_EVENT =
        keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)");

    IPoolManager internal manager;
    SWARMLER internal token;
    SWARMLERHook internal hook;
    PoolRouter internal router;
    PoolKey internal key;

    function _setUp(bool tokenFirst, bool forked) internal {
        if (forked) {
            manager = IPoolManager(MAINNET_MANAGER);
            deal(IMD, address(this), 1e30);
        } else {
            manager = IPoolManager(address(new PoolManager(address(this))));
            MockIMD model = new MockIMD();
            vm.etch(IMD, address(model).code);
            MockIMD(IMD).mint(address(this), 1e30);
        }
        token = _deployToken(tokenFirst);
        hook = _deployHook(manager, address(token));
        router = new PoolRouter(manager);
        key = hook.poolKey();
        assertEq(key.fee, 12500);
        assertEq(key.tickSpacing, 60);
        token.approve(address(router), type(uint256).max);
        IERC20Minimal(IMD).approve(address(router), type(uint256).max);
        manager.initialize(key, Q96);
        _liquidity(LIQUIDITY);
    }

    function _deployToken(bool tokenFirst) internal returns (SWARMLER deployed) {
        bytes32 hash = keccak256(type(SWARMLER).creationCode);
        for (uint256 i;; ++i) {
            address predicted = _predict(bytes32(i), hash);
            if ((predicted < IMD) == tokenFirst) return new SWARMLER{salt: bytes32(i)}();
        }
    }

    function _deployHook(IPoolManager pm, address launchToken) internal returns (SWARMLERHook deployed) {
        bytes memory creation = abi.encodePacked(type(SWARMLERHook).creationCode, abi.encode(pm, launchToken));
        bytes32 hash = keccak256(creation);
        for (uint256 i; i < 200_000; ++i) {
            if (uint160(_predict(bytes32(i), hash)) & 0x3fff != 0x20c4) continue;
            address at;
            bytes32 salt = bytes32(i);
            assembly ("memory-safe") { at := create2(0, add(creation, 32), mload(creation), salt) }
            require(at != address(0), "CREATE2 failed");
            return SWARMLERHook(at);
        }
        revert("salt search exhausted");
    }

    function _predict(bytes32 salt, bytes32 hash) internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, hash)))));
    }

    function _liquidity(int256 amount) internal returns (BalanceDelta) {
        return router.liquidity(key, ModifyLiquidityParams(-600, 600, amount, bytes32(0)), FUNDING, FUNDING);
    }

    function _swap(bool buy, bool exactInput, uint256 amount, uint160 limit)
        internal
        returns (BalanceDelta net, BalanceDelta raw)
    {
        bool zeroForOne = buy ? !hook.tokenIsCurrency0() : hook.tokenIsCurrency0();
        if (limit == 0) limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
        vm.recordLogs();
        net =
            router.swap(key, SwapParams(zeroForOne, exactInput ? -int256(amount) : int256(amount), limit), FUNDING, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(manager) && logs[i].topics[0] == SWAP_EVENT) {
                (int128 d0, int128 d1,,,,) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
                raw = toBalanceDelta(d0, d1);
                found = true;
            }
        }
        assertTrue(found, "real PoolManager Swap event missing");
        _assertSettled();
    }

    function _price() internal view returns (uint160 price) {
        (price,,,) = manager.getSlot0(key.toId());
    }

    function _pairFees() internal returns (uint256 fees) {
        _swap(false, true, 1e21, 0);
        fees = hook.pending();
        assertGt(fees, 0);
    }

    function _assertSettled() internal view {
        assertEq(manager.getNonzeroDeltaCount(), 0);
        assertEq(manager.currencyDelta(address(hook), key.currency0), 0);
        assertEq(manager.currencyDelta(address(hook), key.currency1), 0);
        assertEq(manager.balanceOf(address(hook), uint160(IMD)), hook.pending());
        assertEq(manager.balanceOf(address(hook), uint160(address(token))), hook.pendingBurn());
        assertEq(IERC20Minimal(IMD).balanceOf(address(hook)), 0);
        assertEq(token.balanceOf(address(hook)), 0);
    }

    function _abs(int128 value) internal pure returns (uint256) {
        return uint256(value < 0 ? -int256(value) : int256(value));
    }
}
