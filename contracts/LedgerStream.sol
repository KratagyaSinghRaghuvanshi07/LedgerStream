// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title LedgerStream
 * @dev Streaming payment ledger that records time-based payment streams and withdrawals
 * @notice Similar to a payment stream, but focused on logging and accounting info on-chain
 */
contract LedgerStream {
    address public owner;
    uint256 public nextStreamId;

    struct Stream {
        uint256 id;
        address sender;
        address recipient;
        uint256 deposit;      // total amount allocated
        uint256 withdrawn;    // amount already withdrawn
        uint64  startTime;    // unix timestamp
        uint64  endTime;      // unix timestamp
        bool    isActive;
    }

    // streamId => Stream
    mapping(uint256 => Stream) public streams;

    // sender => streamIds
    mapping(address => uint256[]) public streamsOfSender;

    // recipient => streamIds
    mapping(address => uint256[]) public streamsOfRecipient;

    event StreamCreated(
        uint256 indexed id,
        address indexed sender,
        address indexed recipient,
        uint256 deposit,
        uint64 startTime,
        uint64 endTime
    );

    event Withdrawn(
        uint256 indexed id,
        address indexed recipient,
        uint256 amount,
        uint256 totalWithdrawn
    );

    event StreamCanceled(
        uint256 indexed id,
        address indexed sender,
        uint256 refundToSender,
        uint256 payoutToRecipient
    );

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier streamExists(uint256 id) {
        require(streams[id].sender != address(0), "Stream not found");
        _;
    }

    modifier onlySender(uint256 id) {
        require(streams[id].sender == msg.sender, "Not sender");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Create and fund a new payment stream
     * @param recipient Address receiving the stream
     * @param startTime Start timestamp
     * @param endTime End timestamp
     */
    function createStream(
        address recipient,
        uint64 startTime,
        uint64 endTime
    ) external payable returns (uint256 id) {
        require(recipient != address(0), "Zero recipient");
        require(msg.value > 0, "Deposit = 0");
        require(endTime > startTime, "Invalid time");

        id = nextStreamId++;
        streams[id] = Stream({
            id: id,
            sender: msg.sender,
            recipient: recipient,
            deposit: msg.value,
            withdrawn: 0,
            startTime: startTime,
            endTime: endTime,
            isActive: true
        });

        streamsOfSender[msg.sender].push(id);
        streamsOfRecipient[recipient].push(id);

        emit StreamCreated(id, msg.sender, recipient, msg.value, startTime, endTime);
    }

    /**
     * @dev View: vested amount based on linear schedule
     */
    function vestedAmount(uint256 id)
        public
        view
        streamExists(id)
        returns (uint256)
    {
        Stream memory s = streams[id];

        if (block.timestamp <= s.startTime) return 0;
        if (block.timestamp >= s.endTime) return s.deposit;

        uint256 elapsed = block.timestamp - s.startTime;
        uint256 duration = s.endTime - s.startTime;
        return (s.deposit * elapsed) / duration;
    }

    /**
     * @dev View: withdrawable amount for recipient
     */
    function withdrawable(uint256 id)
        public
        view
        streamExists(id)
        returns (uint256)
    {
        Stream memory s = streams[id];
        if (!s.isActive) return 0;
        uint256 vested = vestedAmount(id);
        if (vested <= s.withdrawn) return 0;
        return vested - s.withdrawn;
    }

    /**
     * @dev Recipient withdraws currently vested amount
     */
    function withdraw(uint256 id) external streamExists(id) {
        Stream storage s = streams[id];
        require(msg.sender == s.recipient, "Not recipient");
        require(s.isActive, "Inactive");

        uint256 amount = withdrawable(id);
        require(amount > 0, "Nothing withdrawable");

        s.withdrawn += amount;

        (bool ok, ) = payable(s.recipient).call{value: amount}("");
        require(ok, "Transfer failed");

        emit Withdrawn(id, s.recipient, amount, s.withdrawn);
    }

    /**
     * @dev Sender cancels stream; pays vested remainder to recipient, refunds unvested to sender
     */
    function cancel(uint256 id)
        external
        streamExists(id)
        onlySender(id)
    {
        Stream storage s = streams[id];
        require(s.isActive, "Already inactive");

        uint256 vested = vestedAmount(id);
        uint256 dueRecipient = vested > s.withdrawn ? (vested - s.withdrawn) : 0;
        uint256 remaining = s.deposit - s.withdrawn - dueRecipient;

        s.isActive = false;

        if (dueRecipient > 0) {
            (bool ok1, ) = payable(s.recipient).call{value: dueRecipient}("");
            require(ok1, "Recipient transfer failed");
        }

        if (remaining > 0) {
            (bool ok2, ) = payable(s.sender).call{value: remaining}("");
            require(ok2, "Sender refund failed");
        }

        emit StreamCanceled(id, s.sender, remaining, dueRecipient);
    }

    /**
     * @dev Get all stream IDs created by a sender
     */
    function getStreamsOfSender(address sender)
        external
        view
        returns (uint256[] memory)
    {
        return streamsOfSender[sender];
    }

    /**
     * @dev Get all stream IDs received by a recipient
     */
    function getStreamsOfRecipient(address recipient)
        external
        view
        returns (uint256[] memory)
    {
        return streamsOfRecipient[recipient];
    }

    /**
     * @dev Get contract ETH balance
     */
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Transfer ownership of LedgerStream admin
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        address prev = owner;
        owner = newOwner;
        emit OwnershipTransferred(prev, newOwner);
    }
}
