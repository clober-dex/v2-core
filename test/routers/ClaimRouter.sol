// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILocker} from "../../src/interfaces/ILocker.sol";
import {IBookManager} from "../../src/interfaces/IBookManager.sol";
import {OrderId, OrderIdLibrary} from "../../src/libraries/OrderId.sol";
import {Currency, CurrencyLibrary} from "../../src/libraries/Currency.sol";

contract ClaimRouter is ILocker {
    using OrderIdLibrary for OrderId;
    using CurrencyLibrary for Currency;

    IBookManager public bookManager;

    constructor(IBookManager _bookManager) {
        bookManager = _bookManager;
    }

    function claim(OrderId id, bytes calldata hookData) external returns (uint256) {
        return abi.decode(bookManager.lock(address(this), abi.encode(msg.sender, id, hookData)), (uint256));
    }

    function lockAcquired(address, bytes calldata data) external returns (bytes memory returnData) {
        (address payer, OrderId id, bytes memory hookData) = abi.decode(data, (address, OrderId, bytes));
        uint256 claimedAmount = bookManager.claim(id, hookData);
        returnData = abi.encode(claimedAmount);
        if (claimedAmount > 0) {
            bookManager.withdraw(bookManager.getBookKey(id.getBookId()).base, payer, claimedAmount);
        }
    }
}
