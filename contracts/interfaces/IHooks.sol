// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./IBookManager.sol";
import "../libraries/OrderId.sol";

interface IHooks {
    function beforeOpen(address sender, IBookManager.BookKey calldata key, bytes calldata hookData)
        external
        returns (bytes4);

    function afterOpen(address sender, IBookManager.BookKey calldata key, bytes calldata hookData)
        external
        returns (bytes4);

    function beforeMake(
        address sender,
        IBookManager.BookKey calldata key,
        IBookManager.MakeParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    function afterMake(
        address sender,
        IBookManager.BookKey calldata key,
        IBookManager.MakeParams calldata params,
        OrderId orderId,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeTake(
        address sender,
        IBookManager.BookKey calldata key,
        IBookManager.TakeParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    function afterTake(
        address sender,
        IBookManager.BookKey calldata key,
        IBookManager.TakeParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeCancel(
        address sender,
        IBookManager.BookKey calldata key,
        IBookManager.CancelParams calldata params,
        bytes calldata hookData
    ) external returns (bytes4);

    function afterCancel(
        address sender,
        IBookManager.BookKey calldata key,
        IBookManager.CancelParams calldata params,
        uint64 canceledAmount,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeClaim(address sender, IBookManager.BookKey calldata key, OrderId orderId, bytes calldata hookData)
        external
        returns (bytes4);

    function afterClaim(
        address sender,
        IBookManager.BookKey calldata key,
        OrderId orderId,
        uint64 claimedAmount,
        bytes calldata hookData
    ) external returns (bytes4);
}
