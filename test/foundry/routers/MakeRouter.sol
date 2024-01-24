// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../contracts/interfaces/ILocker.sol";
import "../../../contracts/interfaces/IBookManager.sol";

contract MakeRouter is ILocker {
    using CurrencyLibrary for Currency;

    IBookManager public bookManager;

    constructor(IBookManager _bookManager) {
        bookManager = _bookManager;
    }

    function make(IBookManager.MakeParams calldata params, bytes calldata hookData)
        external
        payable
        returns (OrderId id, uint256 quoteAmount)
    {
        (id, quoteAmount) =
            abi.decode(bookManager.lock(address(this), abi.encode(msg.sender, params, hookData)), (OrderId, uint256));
        bookManager.transferFrom(address(this), msg.sender, OrderId.unwrap(id));
    }

    function lockAcquired(address, bytes calldata data) external returns (bytes memory returnData) {
        (address payer, IBookManager.MakeParams memory params, bytes memory hookData) =
            abi.decode(data, (address, IBookManager.MakeParams, bytes));
        (OrderId id, uint256 quoteAmount) = bookManager.make(params, hookData);
        returnData = abi.encode(id, quoteAmount);
        if (quoteAmount > 0) {
            if (params.key.quote.isNative()) {
                (bool success,) = address(bookManager).call{value: quoteAmount}("");
                require(success, "MakeRouter: transfer failed");
                (success,) = payable(msg.sender).call{value: address(this).balance}("");
                require(success, "MakeRouter: transfer failed");
            } else {
                IERC20(Currency.unwrap(params.key.quote)).transferFrom(payer, address(bookManager), quoteAmount);
            }
        }
    }
}
