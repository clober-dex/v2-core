// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {OrderId} from "../libraries/OrderId.sol";
import {BookId} from "../libraries/BookId.sol";
import {Tick} from "../libraries/Tick.sol";
import {IBookManager} from "./IBookManager.sol";

interface IController {
    error InvalidAccess();
    error InvalidLength();
    error Deadline();
    error InvalidMarket();
    error ControllerSlippage();
    error ValueTransferFailed();
    error InvalidAction();

    enum Action {
        OPEN,
        MAKE,
        LIMIT,
        TAKE,
        SPEND,
        CLAIM,
        CANCEL
    }

    struct ERC20PermitParams {
        address token;
        uint256 permitAmount;
        PermitSignature signature;
    }

    struct ERC721PermitParams {
        uint256 tokenId;
        PermitSignature signature;
    }

    struct PermitSignature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct OpenBookParams {
        IBookManager.BookKey key;
        bytes hookData;
    }

    struct MakeOrderParams {
        BookId id;
        Tick tick;
        uint256 quoteAmount;
        bytes hookData;
    }

    struct LimitOrderParams {
        BookId takeBookId;
        BookId makeBookId;
        uint256 limitPrice;
        Tick tick;
        uint256 quoteAmount;
        bytes takeHookData;
        bytes makeHookData;
    }

    struct TakeOrderParams {
        BookId id;
        uint256 limitPrice;
        uint256 quoteAmount;
        bytes hookData;
    }

    struct SpendOrderParams {
        BookId id;
        uint256 limitPrice;
        uint256 baseAmount;
        bytes hookData;
    }

    struct ClaimOrderParams {
        OrderId id;
        bytes hookData;
    }

    struct CancelOrderParams {
        OrderId id;
        uint256 leftQuoteAmount;
        bytes hookData;
    }

    function open(OpenBookParams[] calldata openBookParamsList, uint64 deadline) external;

    function getDepth(BookId id, Tick tick) external view returns (uint256);

    function getLowestPrice(BookId id) external view returns (uint256);

    function getOrder(OrderId orderId)
        external
        view
        returns (address provider, uint256 price, uint256 openAmount, uint256 claimableAmount);

    function fromPrice(uint256 price) external pure returns (Tick);

    function toPrice(Tick tick) external pure returns (uint256);

    function execute(
        Action[] calldata actionList,
        bytes[] calldata paramsDataList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata erc20PermitParamsList,
        ERC721PermitParams[] calldata erc721PermitParamsList,
        uint64 deadline
    ) external payable returns (OrderId[] memory ids);

    function make(
        MakeOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable returns (OrderId[] memory ids);

    function take(
        TakeOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable;

    function spend(
        SpendOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable;

    function claim(
        ClaimOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC721PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external;

    function cancel(
        CancelOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC721PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external;
}
