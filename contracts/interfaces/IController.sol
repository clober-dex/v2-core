// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../libraries/OrderId.sol";
import "../libraries/Currency.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IController {
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

    // Todo rename struct
    struct ERC20PermitParams {
        address token;
        uint256 permitAmount;
        PermitSignature signature;
    }

    struct PermitSignature {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    // Todo Consider maker
    struct MakeOrderParams {
        BookId id;
        Tick tick;
        uint256 quoteAmount;
        uint256 claimBounty;
        bytes hookData;
    }

    // Todo Consider recipient
    struct TakeOrderParams {
        BookId id;
        uint256 limitPrice;
        uint256 quoteAmount;
        uint256 maxBaseAmount;
        bytes hookData;
    }

    // Todo Consider recipient
    struct SpendOrderParams {
        BookId id;
        uint256 limitPrice;
        uint256 baseAmount;
        uint256 minQuoteAmount;
        bytes hookData;
    }

    struct ClaimOrderParams {
        OrderId id;
        bytes hookData;
        PermitSignature permitParams;
    }

    struct CancelOrderParams {
        OrderId id;
        uint256 leftQuoteAmount;
        bytes hookData;
        PermitSignature permitParams;
    }

    function execute(
        Action[] memory actionList,
        bytes[] memory orderParamsList,
        ERC20PermitParams[] memory permitParamsList,
        uint64 deadline
    ) external payable returns (OrderId[] memory ids);

    function make(
        MakeOrderParams[] calldata orderParamsList,
        ERC20PermitParams[] memory permitParamsList,
        uint64 deadline
    ) external payable returns (OrderId[] memory ids);

    function take(
        TakeOrderParams[] calldata orderParamsList,
        ERC20PermitParams[] memory permitParamsList,
        uint64 deadline
    ) external payable;

    function spend(
        SpendOrderParams[] calldata orderParamsList,
        ERC20PermitParams[] memory permitParamsList,
        uint64 deadline
    ) external payable;

    function claim(ClaimOrderParams[] calldata orderParamsList, uint64 deadline) external;

    function cancel(CancelOrderParams[] calldata orderParamsList, uint64 deadline) external;

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
