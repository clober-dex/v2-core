// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/IBountyPlatform.sol";
import "./BaseHook.sol";

contract BountyPlatform is BaseHook, IBountyPlatform {
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;

    mapping(BookId => bool) public isRegisteredBook;
    mapping(OrderId => uint256) public bounty;

    constructor(IBookManager bookManager_) BaseHook(bookManager_) {}

    function getHooksCalls() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeOpen: false,
            afterOpen: true,
            beforeMake: false,
            afterMake: false,
            beforeTake: false,
            afterTake: false,
            beforeCancel: false,
            afterCancel: false,
            beforeClaim: false,
            afterClaim: true,
            noOp: false,
            accessLock: false
        });
    }

    function afterOpen(address, IBookManager.BookKey calldata bookKey, bytes calldata)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        isRegisteredBook[bookKey.toId()] = true;
        return BaseHook.afterOpen.selector;
    }

    function offer(OrderId id) external payable {
        (BookId bookId,,) = id.decode();
        if (!isRegisteredBook[bookId]) revert InvalidBook();
        bounty[id] += msg.value;
    }

    function afterClaim(address, OrderId orderId, uint64 claimedAmount, bytes calldata hookData)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        uint256 bountyAmount = bounty[orderId];
        if (claimedAmount > 0 && bountyAmount > 0 && bookManager.getOrder(orderId).open == 0) {
            address hunter = abi.decode(hookData, (address));
            bounty[orderId] = 0;
            (bool success,) = hunter.call{value: bountyAmount}("");
            if (!success) revert BountyTransferFailed();
        }
        return BaseHook.afterClaim.selector;
    }
}
