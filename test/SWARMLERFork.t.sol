// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SWARMLERHookTest} from "./SWARMLERHook.t.sol";

interface IMDMetadata {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// @notice Runs the entire integration suite against Ethereum's deployed PoolManager and IMD.
/// @dev Opt in with forge test --fork-url URL --match-path test/SWARMLERFork.t.sol.
/// No RPC secrets or environment reads are embedded in tests; offline runs explicitly skip.
contract SWARMLERForkToken0Test is SWARMLERHookTest {
    function setUp() public virtual override {
        if (!_hasMainnetFork()) return;
        _setUp(true, true);
    }

    function _hasMainnetFork() internal returns (bool) {
        try vm.activeFork() returns (uint256) {}
        catch {
            vm.skip(true);
            return false;
        }
        assertEq(block.chainid, 1, "fork must be Ethereum mainnet");
        assertGt(MAINNET_MANAGER.code.length, 0, "PoolManager is missing at fork block");
        assertGt(IMD.code.length, 0, "IMD is missing at fork block");
        assertEq(IMDMetadata(IMD).symbol(), "IMD");
        assertEq(IMDMetadata(IMD).decimals(), 18);
        return true;
    }
}

contract SWARMLERForkToken1Test is SWARMLERForkToken0Test {
    function setUp() public override {
        if (!_hasMainnetFork()) return;
        _setUp(false, true);
    }
}
