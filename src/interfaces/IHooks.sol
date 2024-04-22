// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IBookManager} from "./IBookManager.sol";
import {OrderId} from "../libraries/OrderId.sol";

/**
 * @title IHooks
 * @notice Interface for the hooks contract
 */
interface IHooks {
    /**
     * @notice Hook called before opening a new book
     * @param sender The sender of the open transaction
     * @param key The key of the book being opened
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function beforeOpen(address sender, IBookManager.BookKey calldata key, bytes calldata hookData)
        external
        returns (bytes4);

    /**
     * @notice Hook called after opening a new book
     * @param sender The sender of the open transaction
     * @param key The key of the book being opened
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function afterOpen(address sender, IBookManager.BookKey calldata key, bytes calldata hookData)
        external
        returns (bytes4);

    /**
     * @notice Hook called before making a new order
     * @param sender The sender of the make transaction
     * @param params The parameters of the make transaction
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function beforeMake(address sender, IBookManager.MakeParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);

    /**
     * @notice Hook called after making a new order
     * @param sender The sender of the make transaction
     * @param params The parameters of the make transaction
     * @param orderId The id of the order that was made
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function afterMake(
        address sender,
        IBookManager.MakeParams calldata params,
        OrderId orderId,
        bytes calldata hookData
    ) external returns (bytes4);

    /**
     * @notice Hook called before taking an order
     * @param sender The sender of the take transaction
     * @param params The parameters of the take transaction
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function beforeTake(address sender, IBookManager.TakeParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);

    /**
     * @notice Hook called after taking an order
     * @param sender The sender of the take transaction
     * @param params The parameters of the take transaction
     * @param takenUnit The unit that was taken
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function afterTake(
        address sender,
        IBookManager.TakeParams calldata params,
        uint64 takenUnit,
        bytes calldata hookData
    ) external returns (bytes4);

    /**
     * @notice Hook called before canceling an order
     * @param sender The sender of the cancel transaction
     * @param params The parameters of the cancel transaction
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function beforeCancel(address sender, IBookManager.CancelParams calldata params, bytes calldata hookData)
        external
        returns (bytes4);

    /**
     * @notice Hook called after canceling an order
     * @param sender The sender of the cancel transaction
     * @param params The parameters of the cancel transaction
     * @param canceledUnit The unit that was canceled
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function afterCancel(
        address sender,
        IBookManager.CancelParams calldata params,
        uint64 canceledUnit,
        bytes calldata hookData
    ) external returns (bytes4);

    /**
     * @notice Hook called before claiming an order
     * @param sender The sender of the claim transaction
     * @param orderId The id of the order being claimed
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function beforeClaim(address sender, OrderId orderId, bytes calldata hookData) external returns (bytes4);

    /**
     * @notice Hook called after claiming an order
     * @param sender The sender of the claim transaction
     * @param orderId The id of the order being claimed
     * @param claimedUnit The unit that was claimed
     * @param hookData The data passed to the hook
     * @return Returns the function selector if the hook is successful
     */
    function afterClaim(address sender, OrderId orderId, uint64 claimedUnit, bytes calldata hookData)
        external
        returns (bytes4);
}
