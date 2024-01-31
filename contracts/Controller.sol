// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./interfaces/IController.sol";
import "./interfaces/ILocker.sol";
import "./interfaces/IBookManager.sol";
import "./libraries/OrderId.sol";

contract Controller is IController, ILocker {
    using TickLibrary for *;
    using OrderIdLibrary for OrderId;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;
    using CurrencyLibrary for Currency;
    using FeePolicyLibrary for FeePolicy;

    IBookManager private immutable _bookManager;
    address private immutable _provider;

    constructor(address bookManager) {
        _bookManager = IBookManager(bookManager);
        _provider = _bookManager.defaultProvider();
    }

    modifier checkDeadline(uint64 deadline) {
        if (block.timestamp > deadline) revert Deadline();
        _;
    }

    modifier permitERC20(ERC20PermitParams[] calldata permitParamsList) {
        _permitERC20(permitParamsList);
        _;
    }

    function getDepth(BookId id, Tick tick) external view returns (uint256) {
        return uint256(_bookManager.getDepth(id, tick)) * _bookManager.getBookKey(id).unit;
    }

    function getLowestPrice(BookId id) external view returns (uint256) {
        return _bookManager.getRoot(id).toPrice();
    }

    function getOrder(OrderId orderId)
        external
        view
        returns (address provider, uint256 price, uint256 openAmount, uint256 claimableAmount)
    {
        (BookId bookId, Tick tick,) = orderId.decode();
        IBookManager.BookKey memory key = _bookManager.getBookKey(bookId);
        uint256 unit = key.unit;
        price = tick.toPrice();
        IBookManager.OrderInfo memory orderInfo = _bookManager.getOrder(orderId);
        provider = orderInfo.provider;
        openAmount = unit * orderInfo.open;
        FeePolicy makerPolicy = key.makerPolicy;
        claimableAmount = tick.quoteToBase(unit * orderInfo.claimable, false);
        if (makerPolicy.useOutput()) {
            claimableAmount = claimableAmount * uint256(FeePolicyLibrary.RATE_PRECISION - makerPolicy.rate())
                / uint256(FeePolicyLibrary.RATE_PRECISION);
        }
    }

    function fromPrice(uint256 price) external pure returns (Tick) {
        return price.fromPrice();
    }

    function toPrice(Tick tick) external pure returns (uint256) {
        return tick.toPrice();
    }

    function lockAcquired(address, bytes memory data) external returns (bytes memory returnData) {
        if (msg.sender != address(_bookManager)) revert InvalidAccess();
        (address user, Action[] memory actionList, bytes[] memory orderParamsList, address[] memory tokensToSettle) =
            abi.decode(data, (address, Action[], bytes[], address[]));

        uint256 length = actionList.length;
        OrderId[] memory ids = new OrderId[](length);
        uint256 orderIdIndex;

        for (uint256 i = 0; i < length; ++i) {
            Action action = actionList[i];
            if (action == Action.MAKE) {
                ids[orderIdIndex++] = _make(user, abi.decode(orderParamsList[i], (MakeOrderParams)));
            } else if (action == Action.TAKE) {
                _take(abi.decode(orderParamsList[i], (TakeOrderParams)));
            } else if (action == Action.SPEND) {
                _spend(abi.decode(orderParamsList[i], (SpendOrderParams)));
            } else if (action == Action.CLAIM) {
                _claim(abi.decode(orderParamsList[i], (ClaimOrderParams)));
            } else if (action == Action.CANCEL) {
                _cancel(abi.decode(orderParamsList[i], (CancelOrderParams)));
            }
        }

        _settleTokens(user, tokensToSettle);

        assembly {
            mstore(ids, orderIdIndex)
        }
        returnData = abi.encode(ids);
    }

    function execute(
        Action[] calldata actionList,
        bytes[] calldata paramsDataList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata erc20PermitParamsList,
        ERC721PermitParams[] calldata erc721PermitParamsList,
        uint64 deadline
    ) external payable checkDeadline(deadline) returns (OrderId[] memory ids) {
        if (actionList.length != paramsDataList.length) revert InvalidLength();
        _permitERC20(erc20PermitParamsList);
        _permitERC721(erc721PermitParamsList);

        for (uint256 i = 0; i < erc721PermitParamsList.length; ++i) {
            _bookManager.transferFrom(msg.sender, address(this), erc721PermitParamsList[i].tokenId);
        }

        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        bytes memory result = _bookManager.lock(address(this), lockData);

        for (uint256 i = 0; i < erc721PermitParamsList.length; ++i) {
            uint256 orderId = erc721PermitParamsList[i].tokenId;
            IBookManager.OrderInfo memory orderInfo = _bookManager.getOrder(OrderId.wrap(orderId));
            if (orderInfo.claimable > 0 || orderInfo.open > 0) {
                _bookManager.transferFrom(address(this), msg.sender, orderId);
            }
        }

        if (result.length != 0) {
            (ids) = abi.decode(result, (OrderId[]));
        }
        return ids;
    }

    function make(
        MakeOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable checkDeadline(deadline) permitERC20(permitParamsList) returns (OrderId[] memory ids) {
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.MAKE;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        bytes memory result = _bookManager.lock(address(this), lockData);
        (ids) = abi.decode(result, (OrderId[]));
    }

    function take(
        TakeOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable checkDeadline(deadline) permitERC20(permitParamsList) {
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.TAKE;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        _bookManager.lock(address(this), lockData);
    }

    function spend(
        SpendOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable checkDeadline(deadline) permitERC20(permitParamsList) {
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.SPEND;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        _bookManager.lock(address(this), lockData);
    }

    function claim(ClaimOrderParams[] calldata orderParamsList, uint64 deadline) external checkDeadline(deadline) {
        uint256 length = orderParamsList.length;
        for (uint256 i = 0; i < length; ++i) {
            ClaimOrderParams memory params = orderParamsList[i];
            _bookManager.claim(params.id, params.hookData);
        }
    }

    function cancel(
        CancelOrderParams[] calldata orderParamsList,
        ERC721PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external checkDeadline(deadline) {
        _permitERC721(permitParamsList);
        uint256 length = orderParamsList.length;
        for (uint256 i = 0; i < length; ++i) {
            CancelOrderParams memory params = orderParamsList[i];
            (BookId bookId,,) = params.id.decode();
            IBookManager.BookKey memory key = _bookManager.getBookKey(bookId);
            try _bookManager.cancel(
                IBookManager.CancelParams({id: params.id, to: (params.leftQuoteAmount / key.unit).toUint64()}),
                params.hookData
            ) {} catch {}
        }
    }

    function _make(address maker, MakeOrderParams memory params) internal returns (OrderId id) {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);
        uint256 quoteAmount;
        (id, quoteAmount) = _bookManager.make(
            IBookManager.MakeParams({
                key: key,
                tick: params.tick,
                amount: (params.quoteAmount / key.unit).toUint64(),
                provider: address(0)
            }),
            params.hookData
        );
        _bookManager.transferFrom(address(this), maker, OrderId.unwrap(id));
        return id;
    }

    function _take(TakeOrderParams memory params) internal {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

        uint256 leftQuoteAmount = params.quoteAmount;
        uint256 spendBaseAmount;

        uint256 quoteAmount;
        uint256 baseAmount;
        while (leftQuoteAmount > quoteAmount) {
            unchecked {
                leftQuoteAmount -= quoteAmount;
                spendBaseAmount += baseAmount;
            }
            if (_bookManager.getRoot(params.id).toPrice() > params.limitPrice) break;
            (quoteAmount, baseAmount) = _bookManager.take(
                IBookManager.TakeParams({key: key, maxAmount: leftQuoteAmount.divide(key.unit, true).toUint64()}),
                params.hookData
            );
            if (quoteAmount == 0) break;
        }
        if (params.maxBaseAmount < spendBaseAmount) revert ControllerSlippage();
    }

    function _spend(SpendOrderParams memory params) internal {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

        uint256 takenQuoteAmount;
        uint256 leftBaseAmount = params.baseAmount;

        while (leftBaseAmount > 0 && !_bookManager.isEmpty(params.id)) {
            Tick tick = _bookManager.getRoot(params.id);
            if (tick.toPrice() > params.limitPrice) break;
            (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                IBookManager.TakeParams({
                    key: key,
                    maxAmount: (tick.baseToQuote(leftBaseAmount, false) / key.unit).toUint64()
                }),
                params.hookData
            );
            if (quoteAmount == 0) break;

            unchecked {
                leftBaseAmount -= baseAmount;
                takenQuoteAmount += quoteAmount;
            }
        }
        if (takenQuoteAmount < params.minQuoteAmount) revert ControllerSlippage();

        uint256 spendBaseAmount;
        unchecked {
            spendBaseAmount = params.baseAmount - leftBaseAmount;
        }
    }

    function _claim(ClaimOrderParams memory params) internal {
        _bookManager.claim(params.id, params.hookData);
    }

    function _cancel(CancelOrderParams memory params) internal {
        (BookId bookId,,) = params.id.decode();
        IBookManager.BookKey memory key = _bookManager.getBookKey(bookId);
        try _bookManager.cancel(
            IBookManager.CancelParams({id: params.id, to: (params.leftQuoteAmount / key.unit).toUint64()}),
            params.hookData
        ) {} catch {}
    }

    function _settleTokens(address user, address[] memory tokensToSettle) internal {
        Currency native = CurrencyLibrary.NATIVE;
        int256 currencyDelta = _bookManager.currencyDelta(address(this), native);
        if (currencyDelta > 0) {
            native.transfer(address(_bookManager), uint256(currencyDelta));
            _bookManager.settle(native);
        } else if (currencyDelta < 0) {
            _bookManager.withdraw(CurrencyLibrary.NATIVE, user, uint256(-currencyDelta));
        }

        uint256 length = tokensToSettle.length;
        for (uint256 i = 0; i < length; ++i) {
            Currency currency = Currency.wrap(tokensToSettle[i]);
            currencyDelta = _bookManager.currencyDelta(address(this), currency);
            if (currencyDelta > 0) {
                IERC20(tokensToSettle[i]).safeTransferFrom(user, address(_bookManager), uint256(currencyDelta));
                _bookManager.settle(currency);
            } else if (currencyDelta < 0) {
                _bookManager.withdraw(Currency.wrap(tokensToSettle[i]), user, uint256(-currencyDelta));
            }
            uint256 balance = IERC20(tokensToSettle[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(tokensToSettle[i]).transfer(user, balance);
            }
        }
        if (address(this).balance > 0) native.transfer(user, address(this).balance);
    }

    function _permitERC20(ERC20PermitParams[] calldata permitParamsList) internal {
        for (uint256 i = 0; i < permitParamsList.length; ++i) {
            ERC20PermitParams memory permitParams = permitParamsList[i];
            if (permitParams.signature.deadline > 0) {
                try IERC20Permit(permitParams.token).permit(
                    msg.sender,
                    address(this),
                    permitParams.permitAmount,
                    permitParams.signature.deadline,
                    permitParams.signature.v,
                    permitParams.signature.r,
                    permitParams.signature.s
                ) {} catch {}
            }
        }
    }

    function _permitERC721(ERC721PermitParams[] calldata permitParamsList) internal {
        for (uint256 i = 0; i < permitParamsList.length; ++i) {
            PermitSignature memory signature = permitParamsList[i].signature;
            if (signature.deadline > 0) {
                try IERC721Permit(address(_bookManager)).permit(
                    msg.sender, permitParamsList[i].tokenId, signature.deadline, signature.v, signature.r, signature.s
                ) {} catch {}
            }
        }
    }

    receive() external payable {}
}
