// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title BitMath
/// @notice Binary search equivalent of Uniswap's bit-index helpers.
/// @dev Uses constant shifts in place of the upstream packed lookup tables.
library BitMath {
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        require(x > 0);
        if (x >= 1 << 128) {
            x >>= 128;
            r += 128;
        }
        if (x >= 1 << 64) {
            x >>= 64;
            r += 64;
        }
        if (x >= 1 << 32) {
            x >>= 32;
            r += 32;
        }
        if (x >= 1 << 16) {
            x >>= 16;
            r += 16;
        }
        if (x >= 1 << 8) {
            x >>= 8;
            r += 8;
        }
        if (x >= 1 << 4) {
            x >>= 4;
            r += 4;
        }
        if (x >= 1 << 2) {
            x >>= 2;
            r += 2;
        }
        if (x >= 1 << 1) r += 1;
    }

    function leastSignificantBit(uint256 x) internal pure returns (uint8) {
        require(x > 0);
        unchecked {
            return mostSignificantBit(x & (0 - x));
        }
    }
}
