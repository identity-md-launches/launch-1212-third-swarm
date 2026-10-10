// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Fixed supply launch token. The deployer receives the entire supply.
contract SWARMLER {
    string public constant name = "Third Swarm";
    string public constant symbol = "SWARMLER";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 ether;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    error InvalidAddress();
    error InsufficientBalance();
    error InsufficientAllowance();

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert InvalidAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            if (amount > approved) revert InsufficientAllowance();
            allowance[from][msg.sender] = approved - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0) || to == address(0)) revert InvalidAddress();
        uint256 balance = balanceOf[from];
        if (amount > balance) revert InsufficientBalance();
        balanceOf[from] = balance - amount;
        // Read after the debit so self-transfers preserve the balance.
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
