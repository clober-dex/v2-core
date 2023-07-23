// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interfaces/ILimitOrder.sol";
import "./interfaces/IBookManager.sol";
import "./libraries/Book.sol";
import "./libraries/Tick.sol";

// TODO: remove abstract
abstract contract LimitOrder is ILimitOrder {
    using Book for Book.State;
    using TickLibrary for Tick;
    using OrderIdLibrary for OrderId;

    IBookManager private immutable _bookManager;

    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;

    constructor(address bookManager) {
        _bookManager = IBookManager(bookManager);
    }

    function _get(OrderId id) internal view returns (Book.Order memory) {
        return _bookManager.getOrder(id);
    }

    function bookKey(uint256 id) external view returns (IBookManager.BookKey memory) {
        (BookId bookId,,) = OrderId.wrap(id).decode();
        return _bookManager.getBookKey(bookId);
    }

    function maker(uint256 id) external view returns (address) {
        return _get(OrderId.wrap(id)).owner;
    }

    function provider(uint256 id) external view returns (address) {
        return _get(OrderId.wrap(id)).provider;
    }

    function tick(uint256 id) public view returns (Tick) {
        (, Tick t,) = OrderId.wrap(id).decode();
        return t;
    }

    function price(uint256 id) external view returns (uint256) {
        return tick(id).toPrice();
    }

    function amount(uint256 id)
    external
    returns (
        uint64 initial,
        uint64 reduced,
        uint64 filled,
        uint64 claimable
    ) {}

    function reduce(uint256 id, uint64 amount) external {}

    function cancel(uint256 id) external {}

    // TODO: decide if reducing by fill should be counted as reduced or filled. Should reduced be tracked at all?
    function fill(uint256 id, uint64 amount) external {}

    function claim(uint256 id) external {}
}
