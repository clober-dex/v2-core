// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {OrderId} from "../libraries/OrderId.sol";
import {BookId} from "../libraries/BookId.sol";
import {Tick} from "../libraries/Tick.sol";
import {IBookManager} from "./IBookManager.sol";

/**
 * @title IController
 * @notice Interface for the controller contract
 */
interface IController {
    // Error messages
    error InvalidAccess();
    error InvalidLength();
    error Deadline();
    error InvalidMarket();
    error ControllerSlippage();
    error InvalidAction();

    /**
     * @notice Enum for the different actions that can be performed
     */
    enum Action {
        OPEN,
        MAKE,
        LIMIT,
        TAKE,
        SPEND,
        CLAIM,
        CANCEL
    }

    /**
     * @notice Struct for the parameters of the ERC20 permit
     */
    struct ERC20PermitParams {
        address token;
        uint256 permitAmount;
        PermitSignature signature;
    }

    /**
     * @notice Struct for the parameters of the ERC721 permit
     */
    struct ERC721PermitParams {
        uint256 tokenId;
        PermitSignature signature;
    }

    /**
     * @notice Struct for the signature of the permit
     */
    struct PermitSignature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Struct for the parameters of the open book action
     */
    struct OpenBookParams {
        IBookManager.BookKey key;
        bytes hookData;
    }

    /**
     * @notice Struct for the parameters of the make order action
     */
    struct MakeOrderParams {
        BookId id;
        Tick tick;
        uint256 quoteAmount;
        bytes hookData;
    }

    /**
     * @notice Struct for the parameters of the limit order action
     */
    struct LimitOrderParams {
        BookId takeBookId;
        BookId makeBookId;
        uint256 limitPrice;
        Tick tick;
        uint256 quoteAmount;
        bytes takeHookData;
        bytes makeHookData;
    }

    /**
     * @notice Struct for the parameters of the take order action
     */
    struct TakeOrderParams {
        BookId id;
        uint256 limitPrice;
        uint256 quoteAmount;
        uint256 maxBaseAmount;
        bytes hookData;
    }

    /**
     * @notice Struct for the parameters of the spend order action
     */
    struct SpendOrderParams {
        BookId id;
        uint256 limitPrice;
        uint256 baseAmount;
        uint256 minQuoteAmount;
        bytes hookData;
    }

    /**
     * @notice Struct for the parameters of the claim order action
     */
    struct ClaimOrderParams {
        OrderId id;
        bytes hookData;
    }

    /**
     * @notice Struct for the parameters of the cancel order action
     */
    struct CancelOrderParams {
        OrderId id;
        uint256 leftQuoteAmount;
        bytes hookData;
    }

    /**
     * @notice Opens a book
     * @param openBookParamsList The parameters of the open book action
     * @param deadline The deadline for the action
     */
    function open(OpenBookParams[] calldata openBookParamsList, uint64 deadline) external;

    /**
     * @notice Returns the depth of a book
     * @param id The id of the book
     * @param tick The tick of the book
     * @return The depth of the book in quote amount
     */
    function getDepth(BookId id, Tick tick) external view returns (uint256);

    /**
     * @notice Returns the highest price of a book
     * @param id The id of the book
     * @return The highest price of the book with 2**96 precision
     */
    function getHighestPrice(BookId id) external view returns (uint256);

    /**
     * @notice Returns the details of an order
     * @param orderId The id of the order
     * @return provider The provider of the order
     * @return price The price of the order with 2**96 precision
     * @return openAmount The open quote amount of the order
     * @return claimableAmount The claimable base amount of the order
     */
    function getOrder(OrderId orderId)
        external
        view
        returns (address provider, uint256 price, uint256 openAmount, uint256 claimableAmount);

    /**
     * @notice Converts a price to a tick
     * @param price The price to convert
     * @return The tick
     */
    function fromPrice(uint256 price) external pure returns (Tick);

    /**
     * @notice Converts a tick to a price
     * @param tick The tick to convert
     * @return The price with 2**96 precision
     */
    function toPrice(Tick tick) external pure returns (uint256);

    /**
     * @notice Executes a list of actions
     * @dev IMPORTANT: The caller must provide `tokensToSettle` to receive appropriate tokens after execution.
     * @param actionList The list of actions to execute
     * @param paramsDataList The parameters of the actions
     * @param tokensToSettle The tokens to settle
     * @param erc20PermitParamsList The parameters of the ERC20 permits
     * @param erc721PermitParamsList The parameters of the ERC721 permits
     * @param deadline The deadline for the actions
     * @return ids The ids of the orders
     */
    function execute(
        Action[] calldata actionList,
        bytes[] calldata paramsDataList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata erc20PermitParamsList,
        ERC721PermitParams[] calldata erc721PermitParamsList,
        uint64 deadline
    ) external payable returns (OrderId[] memory ids);

    /**
     * @notice Makes a list of orders
     * @dev IMPORTANT: The caller must provide `tokensToSettle` to receive appropriate tokens after execution.
     * @param orderParamsList The list of actions to make
     * @param tokensToSettle The tokens to settle
     * @param permitParamsList The parameters of the permits
     * @param deadline The deadline for the actions
     * @return ids The ids of the orders
     */
    function make(
        MakeOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable returns (OrderId[] memory ids);

    /**
     * @notice Takes a list of orders
     * @dev IMPORTANT: The caller must provide `tokensToSettle` to receive appropriate tokens after execution.
     * @param orderParamsList The list of actions to take
     * @param tokensToSettle The tokens to settle
     * @param permitParamsList The parameters of the permits
     * @param deadline The deadline for the actions
     */
    function take(
        TakeOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable;

    /**
     * @notice Spends to take a list of orders
     * @dev IMPORTANT: The caller must provide `tokensToSettle` to receive appropriate tokens after execution.
     * @param orderParamsList The list of actions to spend
     * @param tokensToSettle The tokens to settle
     * @param permitParamsList The parameters of the permits
     * @param deadline The deadline for the actions
     */
    function spend(
        SpendOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable;

    /**
     * @notice Claims a list of orders
     * @dev IMPORTANT: The caller must provide `tokensToSettle` to receive appropriate tokens after execution.
     * @param orderParamsList The list of actions to claim
     * @param tokensToSettle The tokens to settle
     * @param permitParamsList The parameters of the permits
     * @param deadline The deadline for the actions
     */
    function claim(
        ClaimOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC721PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external;

    /**
     * @notice Cancels a list of orders
     * @dev IMPORTANT: The caller must provide `tokensToSettle` to receive appropriate tokens after execution.
     * @param orderParamsList The list of actions to cancel
     * @param tokensToSettle The tokens to settle
     * @param permitParamsList The parameters of the permits
     * @param deadline The deadline for the actions
     */
    function cancel(
        CancelOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC721PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external;
}
