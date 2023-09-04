// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./libraries/BookId.sol";
import "./libraries/Book.sol";
import "./libraries/OrderId.sol";

contract BookManager is IBookManager {
    using BookIdLibrary for IBookManager.BookKey;
    using TickLibrary for Tick;
    using Book for Book.State;
    using OrderIdLibrary for OrderId;

    mapping(BookId id => Book.State) internal _books;

    constructor() {}

    function _getBook(BookKey memory key) private view returns (Book.State storage) {
        return _books[key.toId()];
    }

    function getBookKey(BookId id) external view returns (BookKey memory) {
        return _books[id].key;
    }

    function getOrder(OrderId id) external view returns (Book.Order memory) {
        (BookId bookId,,) = id.decode();
        return _books[bookId].orders[id];
    }

    function make(IBookManager.MakeParams[] calldata paramsList) external returns (OrderId[] memory ids) {
        ids = new OrderId[](paramsList.length);
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.MakeParams calldata params = paramsList[i];
            Book.State storage book = _getBook(params.key);
            ids[i] =
                book.make(params.key.toId(), params.user, params.tick, params.amount, params.provider, params.bounty);
        }
    }

    function take(IBookManager.TakeParams[] calldata paramsList) external {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.TakeParams calldata params = paramsList[i];
            Book.State storage book = _getBook(params.key);
            (uint256 baseAmount, uint256 rawAmount) =
                book.take(params.key.toId(), msg.sender, params.amount, params.limit);
            // todo: calculate fee
            // todo: check slippage
            // todo: account delta
        }
    }

    function spend(IBookManager.SpendParams[] calldata paramsList) external {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.SpendParams calldata params = paramsList[i];
            Book.State storage book = _getBook(params.key);
            (uint256 baseAmount, uint256 rawAmount) =
                book.spend(params.key.toId(), msg.sender, params.amount, params.limit);
        }
    }

    function reduce(IBookManager.ReduceParams[] calldata paramsList) external {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.ReduceParams calldata params = paramsList[i];
            (BookId bookId,,) = params.id.decode();
            uint64 reducedAmount = _books[bookId].reduce(params.id, params.to);
            // todo: account delta
        }
    }

    function cancel(OrderId[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; ++i) {
            OrderId id = ids[i];
            (BookId bookId,,) = id.decode();
            Book.State storage book = _books[bookId];
            uint64 canceledAmount = book.cancel(id);
            // todo: account delta
        }
    }

    function claim(OrderId[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; ++i) {
            OrderId id = ids[i];
            (BookId bookId,,) = id.decode();
            Book.State storage book = _books[bookId];
            uint256 claimedAmount = book.claim(id);
            // todo: account delta
            // todo: calculate fee
        }
    }

    function collect(address provider, Currency currency) external {}

    function whitelist(address[] calldata provider) external {}

    function delist(address[] calldata provider) external {}
}
