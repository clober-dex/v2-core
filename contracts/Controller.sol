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
        (
            address user,
            Action[] memory actionList,
            bytes[] memory orderParamsList,
            ERC20PermitParams[] memory relatedTokenList
        ) = abi.decode(data, (address, Action[], bytes[], ERC20PermitParams[]));

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
                _claim(user, abi.decode(orderParamsList[i], (ClaimOrderParams)));
            } else if (action == Action.CANCEL) {
                _cancel(user, abi.decode(orderParamsList[i], (CancelOrderParams)));
            }
        }

        _settleTokens(user, relatedTokenList);

        assembly {
            mstore(ids, orderIdIndex)
        }
        returnData = abi.encode(ids);
    }

    function execute(
        Action[] memory actionList,
        bytes[] memory paramsDataList,
        ERC20PermitParams[] memory relatedTokenList,
        uint64 deadline
    ) external payable checkDeadline(deadline) returns (OrderId[] memory ids) {
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, relatedTokenList);
        bytes memory result = _bookManager.lock(address(this), lockData);
        if (result.length != 0) {
            (ids) = abi.decode(result, (OrderId[]));
        }
    }

    function make(
        MakeOrderParams[] calldata orderParamsList,
        ERC20PermitParams[] memory relatedTokenList,
        uint64 deadline
    ) external payable checkDeadline(deadline) returns (OrderId[] memory ids) {
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.MAKE;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, relatedTokenList);
        bytes memory result = _bookManager.lock(address(this), lockData);
        (ids) = abi.decode(result, (OrderId[]));
    }

    function take(
        TakeOrderParams[] calldata orderParamsList,
        ERC20PermitParams[] memory relatedTokenList,
        uint64 deadline
    ) external payable checkDeadline(deadline) {
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.TAKE;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, relatedTokenList);
        _bookManager.lock(address(this), lockData);
    }

    function spend(
        SpendOrderParams[] calldata orderParamsList,
        ERC20PermitParams[] memory relatedTokenList,
        uint64 deadline
    ) external payable checkDeadline(deadline) {
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.SPEND;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, relatedTokenList);
        _bookManager.lock(address(this), lockData);
    }

    function claim(ClaimOrderParams[] calldata orderParamsList, uint64 deadline) external checkDeadline(deadline) {
        uint256 length = orderParamsList.length;
        for (uint256 i = 0; i < length; ++i) {
            ClaimOrderParams memory params = orderParamsList[i];
            _bookManager.claim(params.id, params.hookData);
        }
    }

    function cancel(CancelOrderParams[] calldata orderParamsList, uint64 deadline) external checkDeadline(deadline) {
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
            (quoteAmount, baseAmount) = _bookManager.take(
                IBookManager.TakeParams({key: key, maxAmount: leftQuoteAmount.divide(key.unit, true).toUint64()}),
                params.hookData
            );
            if (quoteAmount == 0) break;
            _bookManager.withdraw(key.quote, address(this), quoteAmount);
        }
        if (params.maxBaseAmount < spendBaseAmount) revert ControllerSlippage();
    }

    function _spend(SpendOrderParams memory params) internal {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

        uint256 takenQuoteAmount;
        uint256 leftBaseAmount = params.baseAmount;

        while (leftBaseAmount > 0 && !_bookManager.isEmpty(params.id)) {
            Tick tick = _bookManager.getRoot(params.id);
            (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                IBookManager.TakeParams({
                    key: key,
                    maxAmount: (tick.baseToQuote(leftBaseAmount, false) / key.unit).toUint64()
                }),
                params.hookData
            );
            if (quoteAmount == 0) break;
            _bookManager.withdraw(key.quote, address(this), quoteAmount);

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

    function _claim(address user, ClaimOrderParams memory params) internal {
        uint256 orderId = OrderId.unwrap(params.id);
        _permitERC721(orderId, params.permitParams);
        if (_bookManager.getApproved(orderId) == address(this)) {
            _bookManager.transferFrom(user, address(this), orderId);
            _bookManager.claim(params.id, params.hookData);
            if (_bookManager.getOrder(params.id).open > 0) {
                _bookManager.transferFrom(address(this), user, orderId);
            }
        }
        _bookManager.claim(params.id, params.hookData);
    }

    function _cancel(address user, CancelOrderParams memory params) internal {
        uint256 orderId = OrderId.unwrap(params.id);
        _permitERC721(orderId, params.permitParams);
        _bookManager.transferFrom(user, address(this), orderId);
        (BookId bookId,,) = params.id.decode();
        IBookManager.BookKey memory key = _bookManager.getBookKey(bookId);
        try _bookManager.cancel(
            IBookManager.CancelParams({id: params.id, to: (params.leftQuoteAmount / key.unit).toUint64()}),
            params.hookData
        ) {} catch {}
        if (_bookManager.getOrder(params.id).claimable > 0 || params.leftQuoteAmount > 0) {
            _bookManager.transferFrom(address(this), user, orderId);
        }
    }

    function _settleTokens(address user, ERC20PermitParams[] memory relatedTokenList) internal {
        uint256 length = relatedTokenList.length;
        _permitERC20(relatedTokenList);
        Currency native = CurrencyLibrary.NATIVE;
        int256 currencyDelta = _bookManager.currencyDelta(address(this), native);
        if (currencyDelta > 0) {
            native.transfer(address(_bookManager), uint256(currencyDelta));
            _bookManager.settle(native);
        }
        for (uint256 i = 0; i < length; ++i) {
            Currency currency = Currency.wrap(relatedTokenList[i].token);
            currencyDelta = _bookManager.currencyDelta(address(this), currency);
            if (currencyDelta > 0) {
                IERC20(relatedTokenList[i].token).safeTransferFrom(user, address(_bookManager), uint256(currencyDelta));
                _bookManager.settle(currency);
            }
            uint256 balance = IERC20(relatedTokenList[i].token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(relatedTokenList[i].token).transfer(user, balance);
            }
            // Todo consider when currencyDelta < 0
        }
        if (address(this).balance > 0) native.transfer(user, address(this).balance);
    }

    function _permitERC20(ERC20PermitParams[] memory permitParamsList) internal {
        uint256 length = permitParamsList.length;
        for (uint256 i = 0; i < length; ++i) {
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

    function _permitERC721(uint256 tokenId, PermitSignature memory permitParams) internal {
        if (permitParams.deadline > 0) {
            try IERC721Permit(address(_bookManager)).permit(
                msg.sender, tokenId, permitParams.deadline, permitParams.v, permitParams.r, permitParams.s
            ) {} catch {}
        }
    }

    receive() external payable {}
}
