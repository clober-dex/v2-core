pragma solidity ^0.8.0;

import "../../../contracts/libraries/Book.sol";

contract BookWrapper {
    using OrderIdLibrary for OrderId;
    using Book for Book.State;

    BookId public immutable BOOK_ID;

    mapping(OrderId => IBookManager.Order) private _orders;
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
        orderIndex = _book.make(_orders, BOOK_ID, tick, amount);
        OrderId id = OrderIdLibrary.encode(BOOK_ID, tick, orderIndex);
        _orders[id] = IBookManager.Order({pending: amount, provider: address(0)});
    }

    function take(uint64 maxAmount) external returns (Tick, uint64) {
        return _book.take(maxAmount);
    }

    function cancel(OrderId orderId, uint64 to) external returns (uint64) {
        return _book.cancel(orderId, _orders[orderId], to);
    }

    function cleanHeap() external {
        _book.cleanHeap();
    }

    function calculateClaimableRawAmount(OrderId orderId) external view returns (uint64) {
        (, Tick tick, uint40 index) = orderId.decode();
        return _book.calculateClaimableRawAmount(_orders[orderId].pending, tick, index);
    }

    function getBookKey() external view returns (IBookManager.BookKey memory) {
        return _book.key;
    }

    function getOrder(OrderId id) external view returns (IBookManager.Order memory) {
        return _orders[id];
    }

    function getRoot() external view returns (Tick) {
        return _book.root();
    }

    function isEmpty() external view returns (bool) {
        return _book.isEmpty();
    }

    function setQueueIndex(Tick tick, uint40 index) external {
        _book.queues[tick].index = index;
    }
}
