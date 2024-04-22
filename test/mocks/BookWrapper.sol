// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../src/libraries/BookId.sol";
import "../../src/libraries/Book.sol";

contract BookWrapper {
    using OrderIdLibrary for OrderId;
    using Book for Book.State;
    using TickLibrary for *;
    using TickBitmap for mapping(uint256 => uint256);

    BookId public immutable BOOK_ID;

    Book.State private _book;

    constructor(BookId bookId) {
        BOOK_ID = bookId;
    }

    function open(IBookManager.BookKey calldata key) external {
        _book.open(key);
    }

    function isOpened() external view returns (bool) {
        return _book.isOpened();
    }

    function checkOpened() external view {
        _book.checkOpened();
    }

    function depth(Tick tick) external view returns (uint64) {
        return _book.depth(tick);
    }

    function make(Tick tick, uint64 amount) external returns (uint40 orderIndex) {
        orderIndex = _book.make(tick, amount, address(0));
    }

    function take(Tick tick, uint64 maxAmount) external returns (uint64) {
        return _book.take(tick, maxAmount);
    }

    function cancel(OrderId orderId, uint64 to) external returns (uint64, uint64) {
        return _book.cancel(orderId, to);
    }

    function claim(OrderId orderId) external returns (uint64) {
        (, Tick tick, uint40 index) = orderId.decode();
        return _book.claim(tick, index);
    }

    function calculateClaimableUnit(OrderId orderId) external view returns (uint64) {
        (, Tick tick, uint40 index) = orderId.decode();
        return _book.calculateClaimableUnit(tick, index);
    }

    function getBookKey() external view returns (IBookManager.BookKey memory) {
        return _book.key;
    }

    function getOrder(OrderId id) external view returns (Book.Order memory) {
        (, Tick tick, uint40 index) = id.decode();
        return _book.getOrder(tick, index);
    }

    function getHighest() external view returns (Tick) {
        return _book.highest();
    }

    function isEmpty() external view returns (bool) {
        return _book.isEmpty();
    }

    function setQueueIndex(Tick tick, uint40 index) external {
        Book.Order[] storage orders = _book.queues[tick].orders;
        assembly {
            sstore(orders.slot, index)
        }
    }

    function tickBitmapHas(Tick tick) external view returns (bool) {
        return _book.tickBitmap.has(tick);
    }
}
