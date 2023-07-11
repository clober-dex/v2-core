// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./libraries/BookId.sol";

contract BookManager {
    using BookIdLibrary for BookKey;

    constructor() {}

    function make(IBookManager.MakeParams[] memory params) external override {}

    function take(IBookManager.TakeParams[] memory params) external override {}

    function reduce(IBookManager.ReduceParams[] memory params) external override {}

    function claim(IBookManager.ClaimParams[] memory params) external override {}
}
