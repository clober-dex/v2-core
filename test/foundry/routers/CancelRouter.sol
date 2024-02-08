// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../contracts/interfaces/ILocker.sol";
import "../../../contracts/interfaces/IBookManager.sol";

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
            (BookId bookId,,) = params.id.decode();
            bookManager.withdraw(bookManager.getBookKey(bookId).quote, payer, canceledAmount);
        }
    }
}
