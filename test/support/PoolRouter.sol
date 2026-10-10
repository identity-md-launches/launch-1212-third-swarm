// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "../../vendor/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../../vendor/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IERC20Minimal} from "../../vendor/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {PoolKey} from "../../vendor/v4-core/src/types/PoolKey.sol";
import {SwapParams, ModifyLiquidityParams} from "../../vendor/v4-core/src/types/PoolOperation.sol";
import {Currency} from "../../vendor/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "../../vendor/v4-core/src/types/BalanceDelta.sol";

/// @dev Integration harness, not a launch router. Pulls only from its entry-point caller.
contract PoolRouter is IUnlockCallback {
    IPoolManager public immutable manager;
    bool private active;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function swap(PoolKey memory key, SwapParams memory params, uint256 maxInput, bytes memory hookData)
        external
        returns (BalanceDelta delta)
    {
        require(!active, "busy");
        active = true;
        Currency input = params.zeroForOne ? key.currency0 : key.currency1;
        require(IERC20Minimal(Currency.unwrap(input)).transferFrom(msg.sender, address(this), maxInput));
        delta = abi.decode(manager.unlock(abi.encode(uint8(0), key, abi.encode(params, hookData))), (BalanceDelta));
        _refund(key);
        active = false;
    }

    function liquidity(PoolKey memory key, ModifyLiquidityParams memory params, uint256 max0, uint256 max1)
        external
        returns (BalanceDelta delta)
    {
        require(!active, "busy");
        active = true;
        require(IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), max0));
        require(IERC20Minimal(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), max1));
        delta = abi.decode(manager.unlock(abi.encode(uint8(1), key, abi.encode(params))), (BalanceDelta));
        _refund(key);
        active = false;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager) && active, "unauthorized");
        (uint8 op, PoolKey memory key, bytes memory action) = abi.decode(data, (uint8, PoolKey, bytes));
        BalanceDelta delta;
        if (op == 0) {
            (SwapParams memory params, bytes memory hookData) = abi.decode(action, (SwapParams, bytes));
            delta = manager.swap(key, params, hookData);
        } else {
            ModifyLiquidityParams memory params = abi.decode(action, (ModifyLiquidityParams));
            (BalanceDelta principalAndFees,) = manager.modifyLiquidity(key, params, "");
            delta = principalAndFees;
        }
        _settle(key.currency0, delta.amount0());
        _settle(key.currency1, delta.amount1());
        return abi.encode(delta);
    }

    function _settle(Currency currency, int128 amount) private {
        if (amount < 0) {
            uint256 owed = uint256(-int256(amount));
            manager.sync(currency);
            currency.transfer(address(manager), owed);
            require(manager.settle() == owed, "settlement mismatch");
        } else if (amount > 0) {
            manager.take(currency, address(this), uint128(amount));
        }
    }

    function _refund(PoolKey memory key) private {
        uint256 balance0 = key.currency0.balanceOfSelf();
        uint256 balance1 = key.currency1.balanceOfSelf();
        if (balance0 != 0) key.currency0.transfer(msg.sender, balance0);
        if (balance1 != 0) key.currency1.transfer(msg.sender, balance1);
    }
}
