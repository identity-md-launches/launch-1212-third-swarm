// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "../vendor/forge-std/src/Test.sol";
import {SWARMLER} from "../src/SWARMLER.sol";

contract SWARMLERTest is Test {
    SWARMLER private token;
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function setUp() public {
        token = new SWARMLER();
    }

    function test_LaunchSupplyAndBranding() public view {
        assertEq(token.name(), "Third Swarm");
        assertEq(token.symbol(), "SWARMLER");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferAndAllowanceConserveSupply(uint256 amount) public {
        amount = bound(amount, 0, token.totalSupply());
        token.transfer(alice, amount);
        vm.prank(alice);
        token.approve(bob, amount);
        vm.prank(bob);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(bob), token.totalSupply());
        vm.prank(bob);
        token.transfer(address(this), amount);
        assertEq(token.balanceOf(address(this)), token.totalSupply());
    }

    function test_SelfTransferAndZeroTransfer() public {
        token.transfer(address(this), token.totalSupply());
        assertEq(token.balanceOf(address(this)), token.totalSupply());
        vm.prank(alice);
        token.transfer(bob, 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_InfiniteAllowanceAndRevocation() public {
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1 ether);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        token.approve(alice, 0);
        vm.prank(alice);
        vm.expectRevert(SWARMLER.InsufficientAllowance.selector);
        token.transferFrom(address(this), bob, 1);
    }

    function test_InvalidTransfersAndApprovalsAreAtomic() public {
        vm.expectRevert(SWARMLER.InvalidAddress.selector);
        token.transfer(address(0), 1);
        vm.expectRevert(SWARMLER.InvalidAddress.selector);
        token.approve(address(0), 1);
        vm.prank(alice);
        vm.expectRevert(SWARMLER.InsufficientBalance.selector);
        token.transfer(bob, 1);
        token.approve(alice, 10);
        vm.prank(alice);
        vm.expectRevert(SWARMLER.InsufficientAllowance.selector);
        token.transferFrom(address(this), bob, 11);
        assertEq(token.allowance(address(this), alice), 10);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function test_FailedTransferFromRestoresAnAlreadyDebitedAllowance() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, 20);
        vm.prank(bob);
        vm.expectRevert(SWARMLER.InsufficientBalance.selector);
        token.transferFrom(alice, bob, 11);
        assertEq(token.allowance(alice, bob), 20);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);

        vm.prank(bob);
        vm.expectRevert(SWARMLER.InvalidAddress.selector);
        token.transferFrom(alice, address(0), 10);
        assertEq(token.allowance(alice, bob), 20);
        vm.prank(bob);
        token.transferFrom(alice, bob, 10);
        assertEq(token.allowance(alice, bob), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 10);
    }

    function test_DelegatedSelfTransferSpendsAllowanceWithoutChangingBalance() public {
        token.approve(alice, 2);
        vm.prank(alice);
        token.transferFrom(address(this), address(this), 2);
        assertEq(token.balanceOf(address(this)), token.totalSupply());
        assertEq(token.allowance(address(this), alice), 0);
        vm.prank(alice);
        vm.expectRevert(SWARMLER.InsufficientAllowance.selector);
        token.transferFrom(address(this), address(this), 1);
        assertEq(token.balanceOf(address(this)), token.totalSupply());
    }

    function test_NoAdminMintOrUpgradeSelectors() public {
        bytes4[8] memory selectors = [
            bytes4(keccak256("mint(address,uint256)")),
            bytes4(keccak256("mint(uint256)")),
            bytes4(keccak256("setOwner(address)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("initialize(address)")),
            bytes4(keccak256("setMinter(address)")),
            bytes4(keccak256("pause()"))
        ];
        for (uint256 i; i < selectors.length; ++i) {
            (bool success,) = address(token).call(abi.encodeWithSelector(selectors[i], alice, uint256(1)));
            assertFalse(success);
            vm.prank(alice);
            (success,) = address(token).call(abi.encodeWithSelector(selectors[i], alice, uint256(1)));
            assertFalse(success);
        }
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(alice), 0);
    }
}
