// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/OrderId.sol";

interface ICloberController {
    error InvalidAccess();
    error Deadline();
    error InvalidMarket();
    error ControllerSlippage();
    error ValueTransferFailed();

    enum Action {
        MAKE,
        TAKE,
        SPEND,
        CLAIM,
        CANCEL
    }

    struct ERC20PermitParams {
        uint256 permitAmount;
        PermitSignature signature;
    }

    struct PermitSignature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct OrderParams {
        MakeOrderParams makeOrderParams;
        TakeOrderParams takeOrderParams;
        SpendOrderParams spendOrderParams;
        ClaimOrderParams claimOrderParams;
        CancelOrderParams cancelOrderParams;
    }

    struct MakeOrderParams {
        BookId id;
        Tick tick;
        uint256 quoteAmount;
        address maker;
        uint256 claimBounty;
        bytes hookData;
        ERC20PermitParams permitParams;
    }

    struct TakeOrderParams {
        BookId id;
        address recipient;
        uint256 limitPrice;
        uint256 quoteAmount;
        uint256 maxBaseAmount;
        bytes hookData;
        ERC20PermitParams permitParams;
    }

    struct SpendOrderParams {
        BookId id;
        address recipient;
        uint256 limitPrice;
        uint256 baseAmount;
        uint256 minQuoteAmount;
        bytes hookData;
        ERC20PermitParams permitParams;
    }

    struct ClaimOrderParams {
        OrderId id;
        bytes hookData;
    }

    struct CancelOrderParams {
        OrderId id;
        // Todo change to quote amount
        uint64 to;
        bytes hookData;
        PermitSignature permitParams;
    }

    function make(MakeOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        returns (OrderId[] memory ids);

    function take(TakeOrderParams[] calldata paramsList, uint64 deadline) external payable;

    function spend(SpendOrderParams[] calldata paramsList, uint64 deadline) external payable;

    function claim(ClaimOrderParams[] calldata paramsList, uint64 deadline) external;

    function cancel(CancelOrderParams[] calldata paramsList, uint64 deadline) external;

    //    function makeAfterClaim(
    //        ClaimOrderParams[] calldata claimOrderParamsList,
    //        MakeOrderParams[] calldata makeOrderParamsList
    //    ) external;
    //
    //    function takeAfterClaim(
    //        ClaimOrderParams[] calldata claimOrderParamsList,
    //        TakeOrderParams[] calldata takeOrderParamsList
    //    ) external;
    //
    //    function spendAfterClaim(
    //        ClaimOrderParams[] calldata claimOrderParamsList,
    //        SpendOrderParams[] calldata spendOrderParamsList
    //    ) external;
}
