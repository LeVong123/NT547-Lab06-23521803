// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// NT547 - Lab 06 - Hop dong rieng cua MSSV 23521803. KHONG deploy len mainnet.

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

// The deployed coordinator must provide verifiable random words and call back
// only after the request has been fulfilled.
interface IRandomnessCoordinator {
    function requestRandomness(uint256 requestId) external;
}

contract StakingPool_1803 {
    address public owner;
    address public immutable randomnessCoordinator;
    mapping(address => uint256) public deposits;
    address[] public participants;
    bool private mutex;
    mapping(address => uint256) public held;
    mapping(address => uint256) public prizeCredit;
    uint256 public cooldownEnd;
    mapping(bytes32 => bool) public claimedKeys;
    uint256 private pendingRequestId;
    uint256 private nextRequestId = 1;
    bool private randomnessPending;
    bool private roundLocked;

    event Deposited(address indexed who, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(tx.origin == owner, "not owner");
        _;
    }

    modifier exclusive() {
        require(!mutex, "reentrant");
        mutex = true;
        _;
        mutex = false;
    }

    constructor(address randomnessCoordinator_) {
        require(randomnessCoordinator_ != address(0), "zero coordinator");
        owner = msg.sender;
        randomnessCoordinator = randomnessCoordinator_;
    }

    function save() external payable {
        deposits[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function ownerWithdraw(uint256 amount) external onlyOwner {
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "withdraw failed");
    }

    function destroyPool() external onlyOwner {
        selfdestruct(payable(msg.sender));
    }

    function enter() external payable exclusive {
        require(!roundLocked, "round locked");
        require(msg.value == 0.01 ether, "0.01 ETH");
        participants.push(msg.sender);
    }

    function settle() external onlyOwner {
        require(participants.length > 0, "no players");
        require(!randomnessPending, "randomness pending");
        uint256 requestId = nextRequestId;
        nextRequestId = requestId + 1;
        pendingRequestId = requestId;
        roundLocked = true;
        randomnessPending = true;
        IRandomnessCoordinator(randomnessCoordinator).requestRandomness(requestId);
    }

    function fulfillRandomness(uint256 requestId, uint256 randomness) external exclusive {
        require(msg.sender == randomnessCoordinator, "not coordinator");
        require(randomnessPending && requestId == pendingRequestId, "invalid request");
        uint256 participantCount = participants.length;
        require(participantCount > 0, "no players");
        uint256 idx = randomness % participantCount;
        address winner = participants[idx];

        // Credit the winner instead of making the oracle callback perform a payout.
        delete participants;
        pendingRequestId = 0;
        randomnessPending = false;
        roundLocked = false;
        prizeCredit[winner] += address(this).balance;
    }

    function claimPrize() external exclusive {
        uint256 prize = prizeCredit[msg.sender];
        require(prize > 0, "no prize");
        prizeCredit[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: prize}("");
        require(ok, "prize failed");
    }

    function saveSafe() external payable exclusive {
        held[msg.sender] += msg.value;
    }

    function redeemSafe() external exclusive {
        uint256 a = held[msg.sender];
        held[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: a}("");
        require(ok, "send failed");
    }

    function vestStep() external onlyOwner {
        // Intentional wall-clock cooldown; timestamp is not used for randomness or authorization.
        // slither-disable-next-line timestamp
        require(block.timestamp >= cooldownEnd, "locked");
        cooldownEnd = block.timestamp + 1 days;
        (bool ok, ) = payable(owner).call{value: address(this).balance / 10}("");
        require(ok, "release failed");
    }

    function redeemCode(string calldata campaign, string calldata code) external {
        bytes32 id = keccak256(abi.encode(campaign, code));
        require(!claimedKeys[id], "used");
        claimedKeys[id] = true;
        deposits[msg.sender] += 1;
    }

    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
