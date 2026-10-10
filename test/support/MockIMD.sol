// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Local test token only. Fork tests use the deployed IMD contract.
contract MockIMD {
    string public constant name = "Test IMD";
    string public constant symbol = "IMD";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 value) external {
        balanceOf[to] += value;
        totalSupply += value;
    }

    function approve(address to, uint256 value) external returns (bool) {
        allowance[msg.sender][to] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}
