// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "../vendor/forge-std/src/Test.sol";
import {SWARMLER} from "../src/SWARMLER.sol";

/// @dev Independent ledger for the launch's custom ERC-20, including failed calls.
contract SwarmTokenHandler is Test {
    SWARMLER public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public acceptedCalls;
    uint256 public rejectedCalls;

    constructor(SWARMLER token_) {
        token = token_;
        actors = [makeAddr("holder A"), makeAddr("holder B"), makeAddr("holder C"), makeAddr("holder D")];
        for (uint256 i; i < actors.length; ++i) {
            expectedBalance[actors[i]] = 1e27 / actors.length;
        }
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % 4];
        address to = _recipient(toSeed);
        uint256 amount = _amount(from, amountSeed);
        bytes4 error = to == address(0)
            ? SWARMLER.InvalidAddress.selector
            : amount > expectedBalance[from] ? SWARMLER.InsufficientBalance.selector : bytes4(0);
        _call(from, abi.encodeCall(token.transfer, (to, amount)), error);
        if (error == bytes4(0)) {
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = _recipient(spenderSeed);
        uint256 amount = _amount(owner, amountSeed);
        bytes4 error = spender == address(0) ? SWARMLER.InvalidAddress.selector : bytes4(0);
        _call(owner, abi.encodeCall(token.approve, (spender, amount)), error);
        if (error == bytes4(0)) expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % 4];
        address spender = actors[spenderSeed % 4];
        address to = _recipient(toSeed);
        uint256 amount = _amount(owner, amountSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        bytes4 error;
        if (allowed != type(uint256).max && amount > allowed) error = SWARMLER.InsufficientAllowance.selector;
        else if (to == address(0)) error = SWARMLER.InvalidAddress.selector;
        else if (amount > expectedBalance[owner]) error = SWARMLER.InsufficientBalance.selector;
        _call(spender, abi.encodeCall(token.transferFrom, (owner, to, amount)), error);
        if (error == bytes4(0)) {
            if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function _amount(address owner, uint256 seed) private view returns (uint256) {
        uint256 balance = expectedBalance[owner];
        uint256 mode = seed % 6;
        if (mode == 0) return 0;
        if (mode == 1) return balance;
        if (mode == 2) return balance + 1;
        if (mode == 3) return type(uint256).max;
        if (mode == 4) return bound(seed, 0, 1e27);
        return bound(seed, 0, balance);
    }

    function _recipient(uint8 seed) private view returns (address) {
        return seed % 5 == 4 ? address(0) : actors[seed % 5];
    }

    function _call(address caller, bytes memory data, bytes4 expectedError) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        if (expectedError == bytes4(0)) {
            assertTrue(success, "valid ERC-20 operation reverted");
            assertTrue(abi.decode(result, (bool)));
            ++acceptedCalls;
        } else {
            assertFalse(success, "invalid ERC-20 operation succeeded");
            assertEq(result, abi.encodeWithSelector(expectedError));
            ++rejectedCalls;
        }
    }
}

contract SWARMLERTokenInvariantTest is Test {
    SWARMLER private token;
    SwarmTokenHandler private handler;

    function setUp() public {
        token = new SWARMLER();
        handler = new SwarmTokenHandler(token);
        for (uint256 i; i < 4; ++i) {
            token.transfer(handler.actors(i), 1e27 / 4);
        }
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_BalancesAndAllowancesMatchAuthorizedOperations() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.balanceOf(owner), handler.expectedBalance(owner));
            sum += token.balanceOf(owner);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
