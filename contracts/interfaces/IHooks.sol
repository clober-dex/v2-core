// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import "./IBookManager.sol";
import "../libraries/OrderId.sol";
import "../libraries/Tick.sol";

interface IHooks {
    function beforeOpen(address sender, IBookManager.BookKey calldata key, bytes calldata hookData)
        external
        returns (bytes4);

    function afterOpen(address sender, IBookManager.BookKey calldata key, bytes calldata hookData)
        external
        returns (bytes4);

    function beforeMake(address sender, IBookManager.MakeParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);

    function afterMake(
        address sender,
        IBookManager.MakeParams calldata params,
        OrderId orderId,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeTake(address sender, IBookManager.TakeParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);

    function afterTake(
        address sender,
        IBookManager.TakeParams calldata params,
        uint64 takenAmount,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeCancel(address sender, IBookManager.CancelParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);

    function afterCancel(
        address sender,
        IBookManager.CancelParams calldata params,
        uint64 canceledAmount,
        bytes calldata hookData
    ) external returns (bytes4);

    function beforeClaim(address sender, OrderId orderId, bytes calldata hookData) external returns (bytes4);

    function afterClaim(address sender, OrderId orderId, uint64 claimedAmount, bytes calldata hookData)
        external
        returns (bytes4);
}
