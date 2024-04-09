// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "../../src/interfaces/IHooks.sol";
import "../../src/libraries/Hooks.sol";
import "../../src/libraries/BookId.sol";

contract MockHooks is IHooks {
    using BookIdLibrary for IBookManager.BookKey;
    using Hooks for IHooks;

    bytes public beforeOpenData;
    bytes public afterOpenData;
    bytes public beforeMakeData;
    bytes public afterMakeData;
    bytes public beforeTakeData;
    bytes public afterTakeData;
    bytes public beforeCancelData;
    bytes public afterCancelData;
    bytes public beforeClaimData;
    bytes public afterClaimData;

    mapping(bytes4 => bytes4) public returnValues;

    function beforeOpen(address, IBookManager.BookKey calldata, bytes calldata hookData) external returns (bytes4) {
        beforeOpenData = hookData;
        bytes4 selector = MockHooks.beforeOpen.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterOpen(address, IBookManager.BookKey calldata, bytes calldata hookData) external returns (bytes4) {
        afterOpenData = hookData;
        bytes4 selector = MockHooks.afterOpen.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeMake(address, IBookManager.MakeParams calldata, bytes calldata hookData) external returns (bytes4) {
        beforeMakeData = hookData;
        bytes4 selector = MockHooks.beforeMake.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterMake(address, IBookManager.MakeParams calldata, OrderId, bytes calldata hookData)
        external
        returns (bytes4)
    {
        afterMakeData = hookData;
        bytes4 selector = MockHooks.afterMake.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeTake(address, IBookManager.TakeParams calldata, bytes calldata hookData) external returns (bytes4) {
        beforeTakeData = hookData;
        bytes4 selector = MockHooks.beforeTake.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterTake(address, IBookManager.TakeParams calldata, uint64, bytes calldata hookData)
        external
        returns (bytes4)
    {
        afterTakeData = hookData;
        bytes4 selector = MockHooks.afterTake.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeCancel(address, IBookManager.CancelParams calldata, bytes calldata hookData)
        external
        returns (bytes4)
    {
        beforeCancelData = hookData;
        bytes4 selector = MockHooks.beforeCancel.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterCancel(address, IBookManager.CancelParams calldata, uint64, bytes calldata hookData)
        external
        returns (bytes4)
    {
        afterCancelData = hookData;
        bytes4 selector = MockHooks.afterCancel.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeClaim(address, OrderId, bytes calldata hookData) external returns (bytes4) {
        beforeClaimData = hookData;
        bytes4 selector = MockHooks.beforeClaim.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterClaim(address, OrderId, uint64, bytes calldata hookData) external returns (bytes4) {
        afterClaimData = hookData;
        bytes4 selector = MockHooks.afterClaim.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }
}
