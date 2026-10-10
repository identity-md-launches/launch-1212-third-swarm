// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "../vendor/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "../vendor/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "../vendor/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Hooks} from "../vendor/v4-core/src/libraries/Hooks.sol";
import {TransientStateLibrary} from "../vendor/v4-core/src/libraries/TransientStateLibrary.sol";
import {Currency} from "../vendor/v4-core/src/types/Currency.sol";
import {PoolKey} from "../vendor/v4-core/src/types/PoolKey.sol";
import {PoolId} from "../vendor/v4-core/src/types/PoolId.sol";
import {SwapParams} from "../vendor/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "../vendor/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta} from "../vendor/v4-core/src/types/BeforeSwapDelta.sol";

/// @notice Immutable SWARMLER/IMD pool hook: actual-fill fees and permissionless batch burns.
/// @dev Claims stay inside PoolManager until redeemed or spent. No token transfers in swap callbacks.
contract SWARMLERHook is IUnlockCallback {
    using TransientStateLibrary for IPoolManager;

    address public constant PAIRED_CURRENCY = 0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint24 public constant POOL_FEE = 12_500;
    int24 public constant TICK_SPACING = 60;
    uint256 public constant FEE_DIVISOR = 100;
    uint256 public constant BATCH_DIVISOR = 4;
    uint256 public constant PRICE_LIMIT_BPS = 300;
    uint256 public constant MAX_REFERENCE_AGE = 50;
    uint256 public constant COOLDOWN = 3600;
    uint160 public constant PERMISSION_FLAGS = 0x20c4;

    // PoolManager accepts limits strictly inside these TickMath endpoints.
    uint160 private constant MIN_SQRT_PRICE = 4295128739;
    uint160 private constant MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342;

    IPoolManager public immutable poolManager;
    address public immutable token;
    bool public immutable tokenIsCurrency0;
    PoolId public immutable poolId;
    bytes32 private immutable _slot0;

    uint256 public pending;
    uint256 public pendingBurn;
    uint256 public lastBatch;
    uint160 public referencePrice;
    uint256 public referenceBlock;
    uint256 public lastPriceBlock;
    uint256 public lastTouchedBlock;
    bool public initialized;
    bool private _hasBatch;
    // 0: idle, 1: sweep unlock requested, 2: batch unlock requested, 3: callback active.
    uint8 private _operation;

    error OnlyPoolManager();
    error InvalidConfiguration();
    error InvalidHookAddress();
    error InvalidPool();
    error AlreadyInitialized();
    error NotInitialized();
    error OperationInProgress();
    error ManagerAlreadyUnlocked();
    error UnexpectedUnlock();
    error CooldownActive();
    error UnrepresentableFee();

    event FeeAccrued(address indexed currency, uint256 amount);
    event Swept(uint256 amount);
    event BatchExecuted(uint256 budget, uint256 spent, uint256 burned, uint160 limit, bool stale);

    constructor(IPoolManager manager_, address token_) {
        if (address(manager_) == address(0) || token_ == address(0) || token_ == PAIRED_CURRENCY) {
            revert InvalidConfiguration();
        }
        if (uint160(address(this)) & Hooks.ALL_HOOK_MASK != PERMISSION_FLAGS) revert InvalidHookAddress();
        poolManager = manager_;
        token = token_;
        tokenIsCurrency0 = token_ < PAIRED_CURRENCY;
        PoolId id = poolKey().toId();
        poolId = id;
        // The v4 pools mapping is storage slot 6; slot0 is its first struct word.
        _slot0 = keccak256(abi.encode(id, uint256(6)));
    }

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        _;
    }

    function getHookPermissions() external pure returns (Hooks.Permissions memory p) {
        p.beforeInitialize = true;
        p.beforeSwap = true;
        p.afterSwap = true;
        p.afterSwapReturnDelta = true;
    }

    function poolKey() public view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(tokenIsCurrency0 ? token : PAIRED_CURRENCY),
            currency1: Currency.wrap(tokenIsCurrency0 ? PAIRED_CURRENCY : token),
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });
    }

    function beforeInitialize(address, PoolKey calldata key, uint160 sqrtPriceX96)
        external
        onlyPoolManager
        returns (bytes4)
    {
        _checkPool(key);
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        referencePrice = sqrtPriceX96;
        referenceBlock = block.number;
        lastPriceBlock = block.number;
        lastTouchedBlock = block.number;
        return IHooks.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        _checkPool(key);
        uint256 magnitude;
        // This also handles int256.min without negating it as an int256.
        unchecked {
            magnitude = params.amountSpecified < 0
                ? uint256(-(params.amountSpecified + 1)) + 1
                : uint256(params.amountSpecified);
        }
        if (magnitude > uint256(type(int256).max) - magnitude / FEE_DIVISOR) revert UnrepresentableFee();
        _touch();
        return (IHooks.beforeSwap.selector, BeforeSwapDelta.wrap(0), 0);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external
        onlyPoolManager
        returns (bytes4, int128)
    {
        _checkPool(key);
        lastPriceBlock = block.number;
        // Exact input: unspecified is output. Exact output: unspecified is input.
        bool unspecifiedIs0 = (params.amountSpecified < 0) != params.zeroForOne;
        int256 actual = unspecifiedIs0 ? int256(delta.amount0()) : int256(delta.amount1());
        uint256 fee = uint256(actual < 0 ? -actual : actual) / FEE_DIVISOR;
        if (fee != 0) {
            Currency currency = unspecifiedIs0 ? key.currency0 : key.currency1;
            if (Currency.unwrap(currency) == token) pendingBurn += fee;
            else pending += fee;
            emit FeeAccrued(Currency.unwrap(currency), fee);
            // mint creates an offsetting hook debit. afterSwapReturnDelta credits that same fee.
            poolManager.mint(address(this), currency.toId(), fee);
        }
        return (IHooks.afterSwap.selector, int128(int256(fee)));
    }

    /// @notice Redeem all collected launch-token claims to the immutable dead address.
    function sweep() external returns (uint256 burned) {
        _startOperation(1);
        _touch();
        burned = abi.decode(poolManager.unlock(""), (uint256));
        _operation = 0;
    }

    /// @notice Spend at most a quarter of accrued IMD in a separate PoolManager unlock.
    /// @return spent Actual IMD used, including the pool LP fee.
    /// @return burned SWARMLER sent directly to DEAD.
    function executeBatch() external returns (uint256 spent, uint256 burned) {
        _startOperation(2);
        if (_hasBatch && block.timestamp - lastBatch < COOLDOWN) revert CooldownActive();
        _touch();
        (spent, burned) = abi.decode(poolManager.unlock(""), (uint256, uint256));
        _operation = 0;
    }

    function unlockCallback(bytes calldata) external onlyPoolManager returns (bytes memory) {
        uint8 operation = _operation;
        if (operation != 1 && operation != 2) revert UnexpectedUnlock();
        _operation = 3;
        if (operation == 1) {
            uint256 amount = pendingBurn;
            pendingBurn = 0;
            emit Swept(amount);
            if (amount != 0) {
                poolManager.burn(address(this), uint160(token), amount);
                poolManager.take(Currency.wrap(token), DEAD, amount);
            }
            return abi.encode(amount);
        }
        return _executeBatch();
    }

    function _executeBatch() private returns (bytes memory) {
        uint256 budget = pending / BATCH_DIVISOR;
        bool stale = block.number - referenceBlock > MAX_REFERENCE_AGE;
        uint160 current = _currentPrice();
        uint160 anchor = referencePrice;
        if (stale) {
            anchor = current;
            budget /= 2;
        }
        uint160 limit = _priceLimit(anchor);
        // An already crossed bound is a zero fill, not an invalid-direction PoolManager swap.
        if (budget == 0 || (tokenIsCurrency0 ? current >= limit : current <= limit)) {
            emit BatchExecuted(budget, 0, 0, limit, stale);
            return abi.encode(uint256(0), uint256(0));
        }

        // v4 skips callbacks when the hook itself is the swap sender. The batch pays only the LP fee.
        BalanceDelta delta = poolManager.swap(poolKey(), SwapParams(!tokenIsCurrency0, -int256(budget), limit), "");
        uint256 spent = uint256(-int256(tokenIsCurrency0 ? delta.amount1() : delta.amount0()));
        uint256 bought = uint256(int256(tokenIsCurrency0 ? delta.amount0() : delta.amount1()));
        pending -= spent;
        lastPriceBlock = block.number;
        // Ceiling division: a dust fill must never start the cooldown, including budgets < 100.
        if (spent != 0 && spent >= (budget + FEE_DIVISOR - 1) / FEE_DIVISOR) {
            _hasBatch = true;
            lastBatch = block.timestamp;
        }
        emit BatchExecuted(budget, spent, bought, limit, stale);
        // Burn exactly the used input claims; a partial fill leaves every unspent claim intact.
        if (spent != 0) poolManager.burn(address(this), uint160(PAIRED_CURRENCY), spent);
        if (bought != 0) poolManager.take(Currency.wrap(token), DEAD, bought);
        return abi.encode(spent, bought);
    }

    function _startOperation(uint8 operation) private {
        if (_operation != 0) revert OperationInProgress();
        if (!initialized) revert NotInitialized();
        if (poolManager.isUnlocked()) revert ManagerAlreadyUnlocked();
        _operation = operation;
    }

    function _checkPool(PoolKey calldata key) private view {
        if (PoolId.unwrap(key.toId()) != PoolId.unwrap(poolId)) revert InvalidPool();
    }

    function _currentPrice() private view returns (uint160) {
        return uint160(uint256(poolManager.extsload(_slot0)));
    }

    function _touch() private {
        if (lastTouchedBlock != block.number) {
            // Before the first swap this is exactly the previous block's closing sqrt price.
            referencePrice = _currentPrice();
            referenceBlock = lastPriceBlock;
            lastTouchedBlock = block.number;
        }
    }

    function _priceLimit(uint160 anchor) private view returns (uint160) {
        uint256 limit;
        if (tokenIsCurrency0) {
            limit = uint256(anchor) * (10_000 + PRICE_LIMIT_BPS) / 10_000;
            if (limit >= MAX_SQRT_PRICE) limit = MAX_SQRT_PRICE - 1;
        } else {
            // Reciprocal orientation: round up to avoid exceeding the same 3% sqrt-price cap.
            limit = (uint256(anchor) * 10_000 + (10_000 + PRICE_LIMIT_BPS) - 1) / (10_000 + PRICE_LIMIT_BPS);
            if (limit <= MIN_SQRT_PRICE) limit = MIN_SQRT_PRICE + 1;
        }
        return uint160(limit);
    }
}
