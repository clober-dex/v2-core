// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./libraries/BookId.sol";
import "./libraries/Book.sol";
import "./libraries/OrderId.sol";

contract BookManager is IBookManager {
    using BookIdLibrary for IBookManager.BookKey;
    using Book for Book.State;
    using OrderIdLibrary for OrderId;

    mapping(BookId id => Book.State) internal _books;

    constructor() {}

    function _getBook(BookKey memory key) private view returns (Book.State storage) {
        return _books[key.toId()];
    }

    function getBookKey(BookId id) external view override returns (BookKey memory) {
        return _books[id].key;
    }

    function getOrder(OrderId id) external override view returns (Book.Order memory) {
        (BookId bookId,, uint40 index) = id.decode();
        return _books[bookId].orders[index];
    }

    function make(IBookManager.MakeParams[] calldata paramsList) external override returns (OrderId[] memory ids) {
        ids = new OrderId[](paramsList.length);
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.MakeParams calldata params = paramsList[i];
            Book.State storage book = _getBook(params.key);
            ids[i] = book.make(
                params.key.toId(),
                params.user,
                params.tick,
                params.amount,
                params.provider,
                params.bounty
            );
        }
    }

    function take(IBookManager.TakeParams[] calldata paramsList) external override {}

    function spend(IBookManager.SpendParams[] calldata paramsList) external override {}

    function reduce(IBookManager.ReduceParams[] calldata paramsList) external override {}

    function cancel(uint256[] calldata ids) external override {}

    function claim(uint256[] calldata ids) external override {}

    function collect(address provider, Currency currency) external override {}

    function whitelist(address[] calldata provider) external override {}

    function delist(address[] calldata provider) external override {}
}
