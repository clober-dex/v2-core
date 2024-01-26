// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./interfaces/ICloberController.sol";
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

    modifier flushNative() {
        _;
        if (address(this).balance > 0) {
            (bool success,) = msg.sender.call{value: address(this).balance}("");
            if (!success) revert ValueTransferFailed();
        }
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
        returns (address provider, uint256 price, uint256 openQuoteAmount, uint256 claimableQuoteAmount)
    {
        (BookId bookId, Tick tick,) = orderId.decode();
        uint256 unit = _bookManager.getBookKey(bookId).unit;
        price = tick.toPrice();
        IBookManager.OrderInfo memory orderInfo = _bookManager.getOrder(orderId);
        provider = orderInfo.provider;
        openQuoteAmount = unit * orderInfo.open;
        claimableQuoteAmount = unit * orderInfo.claimable;
    }

    function fromPrice(uint256 price) external pure returns (Tick) {
        return price.fromPrice();
    }

    function toPrice(Tick tick) external pure returns (uint256) {
        return tick.toPrice();
    }

    function lockAcquired(address, bytes memory data) external returns (bytes memory returnData) {
        if (msg.sender != address(_bookManager)) revert InvalidAccess();
        (address user, Action[] memory actionList, bytes[] memory paramsList) =
            abi.decode(data, (address, Action[], bytes[]));
        uint256 length = actionList.length;
        OrderId[] memory ids = new OrderId[](length);
        uint256 orderIdIndex;
        for (uint256 i = 0; i < length; ++i) {
            Action action = actionList[i];
            if (action == Action.MAKE) {
                ids[orderIdIndex++] = _make(user, abi.decode(paramsList[i], (MakeOrderParams)));
            } else if (action == Action.TAKE) {
                _take(user, abi.decode(paramsList[i], (TakeOrderParams)));
            } else if (action == Action.SPEND) {
                _spend(user, abi.decode(paramsList[i], (SpendOrderParams)));
            } else if (action == Action.CLAIM) {
                _claim(abi.decode(paramsList[i], (ClaimOrderParams)));
            } else if (action == Action.CANCEL) {
                _cancel(abi.decode(paramsList[i], (CancelOrderParams)));
            }
        }
        assembly {
            mstore(ids, orderIdIndex)
        }
        returnData = abi.encode(ids);
    }

    function action(Action actionList, bytes[] memory paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
        returns (OrderId[] memory ids)
    {
        bytes memory lockData = abi.encode(msg.sender, actionList, abi.encode(paramsList));
        bytes memory result = _bookManager.lock(address(this), lockData);
        if (result.length != 0) {
            (ids) = abi.decode(result, (OrderId[]));
        }
    }

    function make(MakeOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
        returns (OrderId[] memory ids)
    {
        uint256 length = paramsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.MAKE;
            paramsDataList[i] = abi.encode(paramsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList);
        bytes memory result = _bookManager.lock(address(this), lockData);
        (ids) = abi.decode(result, (OrderId[]));
    }

    function take(TakeOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
    {
        uint256 length = paramsList.length;
        Action[] memory actionList = new Action[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.TAKE;
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, abi.encode(paramsList));
        _bookManager.lock(address(this), lockData);
    }

    function spend(SpendOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
    {
        uint256 length = paramsList.length;
        Action[] memory actionList = new Action[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.SPEND;
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, abi.encode(paramsList));
        _bookManager.lock(address(this), lockData);
    }

    function claim(ClaimOrderParams[] calldata paramsList, uint64 deadline) external checkDeadline(deadline) {
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; ++i) {
            _claim(paramsList[i]);
        }
    }

    function cancel(CancelOrderParams[] calldata paramsList, uint64 deadline) external checkDeadline(deadline) {
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; ++i) {
            _cancel(paramsList[i]);
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

        _permitERC20(Currency.unwrap(key.quote), params.permitParams);
        if (key.quote.isNative()) {
            key.quote.transfer(address(_bookManager), quoteAmount);
        } else {
            IERC20(Currency.unwrap(key.quote)).safeTransferFrom(maker, address(_bookManager), quoteAmount);
        }
        _bookManager.settle(key.quote);
        _bookManager.transferFrom(address(this), maker, OrderId.unwrap(id));
        return id;
    }

    function _take(address taker, TakeOrderParams memory params) internal {
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

        _permitERC20(Currency.unwrap(key.base), params.permitParams);
        if (key.base.isNative()) {
            key.base.transfer(address(_bookManager), spendBaseAmount);
        } else {
            IERC20(Currency.unwrap(key.base)).safeTransferFrom(taker, address(_bookManager), spendBaseAmount);
        }
        _bookManager.settle(key.base);
    }

    function _spend(address spender, SpendOrderParams memory params) internal {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

        uint256 takenQuoteAmount;
        uint256 leftBaseAmount = params.baseAmount;

        while (leftBaseAmount > 0 && !_bookManager.isEmpty(params.id)) {
            Tick tick = _bookManager.getRoot(params.id);
            (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                IBookManager.TakeParams({key: key, maxAmount: tick.baseToRaw(leftBaseAmount, false)}), params.hookData
            );
            if (quoteAmount == 0) break;
            _bookManager.withdraw(key.quote, address(this), quoteAmount);

            unchecked {
                leftBaseAmount -= baseAmount;
                takenQuoteAmount += quoteAmount;
            }
        }
        if (takenQuoteAmount < params.minQuoteAmount) revert ControllerSlippage();

        _permitERC20(Currency.unwrap(key.base), params.permitParams);

        uint256 spendBaseAmount;
        unchecked {
            spendBaseAmount = params.baseAmount - leftBaseAmount;
        }
        if (key.base.isNative()) {
            key.base.transfer(address(_bookManager), spendBaseAmount);
        } else {
            IERC20(Currency.unwrap(key.base)).safeTransferFrom(spender, address(_bookManager), spendBaseAmount);
        }
        _bookManager.settle(key.base);
    }

    function _claim(ClaimOrderParams memory params) internal {
        _bookManager.claim(params.id, params.hookData);
    }

    function _cancel(CancelOrderParams memory params) internal {
        (BookId bookId,,) = params.id.decode();
        _permitERC721(OrderId.unwrap(params.id), params.permitParams);
        try _bookManager.cancel(
            IBookManager.CancelParams({
                id: params.id,
                to: (params.leftQuoteAmount / _bookManager.getBookKey(bookId).unit).toUint64()
            }),
            params.hookData
        ) {} catch {}
    }

    function _permitERC20(address token, ERC20PermitParams memory p) internal {
        if (p.signature.deadline > 0) {
            try IERC20Permit(token).permit(
                msg.sender,
                address(this),
                p.permitAmount,
                p.signature.deadline,
                p.signature.v,
                p.signature.r,
                p.signature.s
            ) {} catch {}
        }
    }

    function _permitERC721(uint256 tokenId, PermitSignature memory p) internal {
        if (p.deadline > 0) {
            try IERC721Permit(address(_bookManager)).permit(msg.sender, tokenId, p.deadline, p.v, p.r, p.s) {} catch {}
        }
    }
}
