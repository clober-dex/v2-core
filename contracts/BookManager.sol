// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./libraries/BookId.sol";

contract BookManager is IBookManager {
    using BookIdLibrary for IBookManager.BookKey;

    constructor() {}

    function make(IBookManager.MakeParams[] memory paramsList) external override returns (uint256 orderIndex) {}

    function take(IBookManager.TakeParams[] memory paramsList) external override {}

    function reduce(IBookManager.ReduceParams[] memory paramsList) external override {}

    function claim(IBookManager.ClaimParams[] memory paramsList) external override {}
}
