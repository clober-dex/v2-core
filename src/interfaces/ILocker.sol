// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title ILocker
 * @notice Interface for the locker contract
 */
interface ILocker {
    /**
     * @notice Called by the book manager on `msg.sender` when a lock is acquired
     * @param data The data that was passed to the call to lock
     * @return Any data that you want to be returned from the lock call
     */
    function lockAcquired(address lockCaller, bytes calldata data) external returns (bytes memory);
}
