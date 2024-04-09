// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILocker} from "../../src/interfaces/ILocker.sol";
import {IBookManager} from "../../src/interfaces/IBookManager.sol";
import {Currency, CurrencyLibrary} from "../../src/libraries/Currency.sol";

contract OpenRouter is ILocker {
    using CurrencyLibrary for Currency;

    IBookManager public bookManager;

    constructor(IBookManager _bookManager) {
        bookManager = _bookManager;
    }

    function open(IBookManager.BookKey calldata key, bytes calldata hookData) external {
        bookManager.lock(address(this), abi.encode(key, hookData));
    }

    function lockAcquired(address, bytes calldata data) external returns (bytes memory) {
        (IBookManager.BookKey memory key, bytes memory hookData) = abi.decode(data, (IBookManager.BookKey, bytes));
        bookManager.open(key, hookData);
        return "";
    }
}
