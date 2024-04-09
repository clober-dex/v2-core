// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ILocker} from "../../src/interfaces/ILocker.sol";
import {IBookManager} from "../../src/interfaces/IBookManager.sol";
import {Currency, CurrencyLibrary} from "../../src/libraries/Currency.sol";

contract TakeRouter is ILocker {
    using CurrencyLibrary for Currency;

    IBookManager public bookManager;

    constructor(IBookManager _bookManager) {
        bookManager = _bookManager;
    }

    function take(IBookManager.TakeParams calldata params, bytes calldata hookData)
        external
        payable
        returns (uint256 quoteAmount, uint256 baseAmount)
    {
        (quoteAmount, baseAmount) =
            abi.decode(bookManager.lock(address(this), abi.encode(msg.sender, params, hookData)), (uint256, uint256));
        if (address(this).balance > 0) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "TakeRouter: transfer failed");
        }
    }

    function lockAcquired(address, bytes calldata data) external returns (bytes memory returnData) {
        (address payer, IBookManager.TakeParams memory params, bytes memory hookData) =
            abi.decode(data, (address, IBookManager.TakeParams, bytes));
        (uint256 quoteAmount, uint256 baseAmount) = bookManager.take(params, hookData);
        returnData = abi.encode(quoteAmount, baseAmount);
        if (quoteAmount > 0) {
            bookManager.withdraw(params.key.quote, payer, quoteAmount);
        }
        if (baseAmount > 0) {
            if (params.key.base.isNative()) {
                (bool success,) = address(bookManager).call{value: baseAmount}("");
                require(success, "TakeRouter: transfer failed");
            } else {
                IERC20(Currency.unwrap(params.key.base)).transferFrom(payer, address(bookManager), baseAmount);
            }
            bookManager.settle(params.key.base);
        }
    }

    receive() external payable {}
}
