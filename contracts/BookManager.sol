// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./libraries/BookId.sol";
import "./libraries/Book.sol";

contract BookManager is IBookManager {
    using BookIdLibrary for IBookManager.BookKey;
    using Book for Book.State;

    constructor() {}

    function make(IBookManager.MakeParams[] memory paramsList) external override returns (uint256 id) {}

    function take(IBookManager.TakeParams[] memory paramsList) external override {}

    function spend(IBookManager.SpendParams[] memory paramsList) external override {}

    function reduce(IBookManager.ReduceParams[] memory paramsList) external override {}

    function cancel(uint256[] memory ids) external override {}

    function claim(uint256[] memory ids) external override {}

    function collect(address provider, Currency currency) external override {}

    function whitelist(address provider) external override {}

    function blacklist(address provider) external override {}

    function delist(address provider) external override {}
}
