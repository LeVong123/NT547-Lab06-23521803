// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// NT547 - Lab 06 - Hop dong rieng cua MSSV 23521803. KHONG deploy len mainnet.

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract StakingPool_1803 {
    address public owner;
    mapping(address => uint256) public deposits;
    address[] public participants;
    bool private mutex;
    mapping(address => uint256) public held;
    uint256 public cooldownEnd;
    mapping(bytes32 => bool) public claimedKeys;

    event Deposited(address indexed who, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier exclusive() {
        require(!mutex, "reentrant");
        mutex = true;
        _;
        mutex = false;
    }

    constructor() {
        owner = msg.sender;
    }

    function save() external payable {
        deposits[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function ownerWithdraw(uint256 amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
    }

    function destroyPool() external {
        selfdestruct(payable(msg.sender));
    }

    function enter() external payable {
        require(msg.value == 0.01 ether, "0.01 ETH");
        participants.push(msg.sender);
    }

    function settle() external onlyOwner {
        require(participants.length > 0, "no players");
        uint256 idx = block.timestamp % participants.length;
        address winner = participants[idx];
        delete participants;
        (bool ok, ) = payable(winner).call{value: address(this).balance}("");
        require(ok, "prize failed");
    }

    function saveSafe() external payable exclusive {
        held[msg.sender] += msg.value;
    }

    function redeemSafe() external exclusive {
        uint256 a = held[msg.sender];
        (bool ok, ) = msg.sender.call{value: a}("");
        require(ok, "send failed");
        held[msg.sender] = 0;
    }

    function vestStep() external onlyOwner {
        require(block.timestamp >= cooldownEnd, "locked");
        cooldownEnd = block.timestamp + 1 days;
        (bool ok, ) = payable(owner).call{value: address(this).balance / 10}("");
        require(ok, "release failed");
    }

    function redeemCode(string calldata campaign, string calldata code) external {
        bytes32 id = keccak256(abi.encodePacked(campaign, code));
        require(!claimedKeys[id], "used");
        claimedKeys[id] = true;
        deposits[msg.sender] += 1;
    }

    function updateOwner(address newOwner) external {
        require(tx.origin == owner, "not owner");
        require(newOwner != address(0), "zero");
        owner = newOwner;
    }
}
