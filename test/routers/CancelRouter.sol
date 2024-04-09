// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILocker} from "../../src/interfaces/ILocker.sol";
import {IBookManager} from "../../src/interfaces/IBookManager.sol";
import {OrderId, OrderIdLibrary} from "../../src/libraries/OrderId.sol";
import {Currency, CurrencyLibrary} from "../../src/libraries/Currency.sol";

contract CancelRouter is ILocker {
    using OrderIdLibrary for OrderId;
    using CurrencyLibrary for Currency;

    IBookManager public bookManager;

    constructor(IBookManager _bookManager) {
        bookManager = _bookManager;
    }

    function cancel(IBookManager.CancelParams calldata params, bytes calldata hookData) external returns (uint256) {
        return abi.decode(bookManager.lock(address(this), abi.encode(msg.sender, params, hookData)), (uint256));
    }

    function lockAcquired(address, bytes calldata data) external returns (bytes memory returnData) {
        (address payer, IBookManager.CancelParams memory params, bytes memory hookData) =
            abi.decode(data, (address, IBookManager.CancelParams, bytes));
        uint256 canceledAmount = bookManager.cancel(params, hookData);
        returnData = abi.encode(canceledAmount);

        if (canceledAmount > 0) {
            bookManager.withdraw(bookManager.getBookKey(params.id.getBookId()).quote, payer, canceledAmount);
        }
    }
}
