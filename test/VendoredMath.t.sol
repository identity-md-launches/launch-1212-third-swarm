// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "../vendor/forge-std/src/Test.sol";
import {BitMath} from "../vendor/v4-core/src/libraries/BitMath.sol";
import {FullMath} from "../vendor/v4-core/src/libraries/FullMath.sol";

/// @notice Regression tests for the two explicitly documented vendor math adaptations.
contract VendoredMathTest is Test {
    function test_AllBitBoundaries() public pure {
        for (uint256 i; i < 256; ++i) {
            uint256 x = uint256(1) << i;
            assertEq(BitMath.mostSignificantBit(x), i);
            assertEq(BitMath.leastSignificantBit(x), i);
            if (i > 0) assertEq(BitMath.mostSignificantBit(x - 1), i - 1);
            assertEq(BitMath.leastSignificantBit(x | 1), 0);
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_BitIndices(uint256 x) public pure {
        if (x == 0) x = 1;
        uint256 highest = BitMath.mostSignificantBit(x);
        uint256 lowest = BitMath.leastSignificantBit(x);
        assertEq(x >> highest, 1);
        assertEq((x >> lowest) & 1, 1);
        assertEq(x & ((uint256(1) << lowest) - 1), 0);
        assertLe(lowest, highest);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_FullMathDivisionIdentity(uint256 a, uint256 b, uint256 seed) public pure {
        (uint256 high, uint256 low) = _multiply512(a, b);
        uint256 denominator = seed > high ? seed : high + 1;
        uint256 q = FullMath.mulDiv(a, b, denominator);
        uint256 remainder = mulmod(a, b, denominator);
        (uint256 qHigh, uint256 qLow) = _multiply512(q, denominator);
        unchecked {
            uint256 restoredLow = qLow + remainder;
            uint256 restoredHigh = qHigh + (restoredLow < qLow ? 1 : 0);
            assertEq(restoredLow, low);
            assertEq(restoredHigh, high);
        }
        if (q < type(uint256).max) {
            assertEq(FullMath.mulDivRoundingUp(a, b, denominator), q + (remainder == 0 ? 0 : 1));
        }
    }

    function test_FullMathMaxAndPhantomOverflow() public pure {
        assertEq(FullMath.mulDiv(type(uint256).max, type(uint256).max, type(uint256).max), type(uint256).max);
        assertEq(FullMath.mulDiv(uint256(1) << 200, uint256(1) << 100, uint256(1) << 60), uint256(1) << 240);
        assertEq(FullMath.mulDiv(123, 456, 7), 8012);
        assertEq(FullMath.mulDivRoundingUp(123, 456, 7), 8013);
    }

    function test_ZeroAndOverflowRevert() public {
        vm.expectRevert();
        this.msb(0);
        vm.expectRevert();
        this.lsb(0);
        vm.expectRevert();
        this.divide(1, 1, 0);
        vm.expectRevert();
        this.divide(type(uint256).max, 2, 1);
    }

    function msb(uint256 x) external pure returns (uint256) {
        return BitMath.mostSignificantBit(x);
    }

    function lsb(uint256 x) external pure returns (uint256) {
        return BitMath.leastSignificantBit(x);
    }

    function divide(uint256 a, uint256 b, uint256 d) external pure returns (uint256) {
        return FullMath.mulDiv(a, b, d);
    }

    /// @dev Independent 128-bit limb multiplication, unlike FullMath's CRT reconstruction.
    function _multiply512(uint256 a, uint256 b) private pure returns (uint256 high, uint256 low) {
        uint256 mask = type(uint128).max;
        uint256 a0 = a & mask;
        uint256 a1 = a >> 128;
        uint256 b0 = b & mask;
        uint256 b1 = b >> 128;
        uint256 p00 = a0 * b0;
        uint256 middle = (p00 >> 128) + (a1 * b0 & mask) + (a0 * b1 & mask);
        high = a1 * b1 + (a1 * b0 >> 128) + (a0 * b1 >> 128) + (middle >> 128);
        low = (middle << 128) | (p00 & mask);
    }
}
