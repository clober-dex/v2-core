// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./IHooks.sol";

interface IBountyPlatform {
    error BountyTransferFailed();
    error InvalidBook();

    function isRegisteredBook(BookId bookId) external view returns (bool);

    function bounty(OrderId orderId) external view returns (uint256);

    function offer(OrderId orderId) external payable;
}
