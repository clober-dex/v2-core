// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../contracts/interfaces/ILocker.sol";
import "../../../contracts/interfaces/IBookManager.sol";

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
            (BookId bookId,,) = id.decode();
            bookManager.withdraw(bookManager.getBookKey(bookId).base, payer, claimedAmount);
        }
    }
}