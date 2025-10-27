// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title LedgerStream
 * @dev A simple decentralized ledger that records transactions between users.
 * Each transaction is stored on-chain with sender, receiver, and amount details.
 */
contract LedgerStream {

    struct Transaction {
        address sender;
        address receiver;
        uint256 amount;
        uint256 timestamp;
    }

    Transaction[] private transactions;

    event TransactionRecorded(address indexed sender, address indexed receiver, uint256 amount, uint256 timestamp);

    /**
     * @dev Record a transaction between sender and receiver.
     * @param _receiver Address of the receiver.
     * @param _amount Amount transferred (in wei).
     */
    function recordTransaction(address _receiver, uint256 _amount) external {
        require(_receiver != address(0), "Invalid receiver address");
        require(_amount > 0, "Amount must be greater than zero");

        transactions.push(Transaction(msg.sender, _receiver, _amount, block.timestamp));
        emit TransactionRecorded(msg.sender, _receiver, _amount, block.timestamp);
    }

    /**
     * @dev Get the total number of transactions stored.
     * @return Total count of transactions.
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev Retrieve a specific transaction by index.
     * @param index The index of the transaction.
     * @return sender Receiver Amount Timestamp
     */
    function getTransaction(uint256 index) external view returns (address, address, uint256, uint256) {
        require(index < transactions.length, "Invalid transaction index");
        Transaction memory txn = transactions[index];
        return (txn.sender, txn.receiver, txn.amount, txn.timestamp);
    }
}
