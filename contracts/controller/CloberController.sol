// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICloberController.sol";
import "../interfaces/ILocker.sol";
import "../interfaces/IBookManager.sol";
import "../libraries/OrderId.sol";

contract CloberController is ICloberController, ILocker {
    using TickLibrary for *;
    using OrderIdLibrary for OrderId;
    using SafeERC20 for IERC20;
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

    function fromPrice(uint256 price) external view returns (Tick) {
        return price.fromPrice();
    }

    function toPrice(Tick tick) external view returns (uint256) {
        return tick.toPrice();
    }

    function lockAcquired(address, bytes memory data) external returns (bytes memory returnData) {
        if (msg.sender != address(_bookManager)) revert InvalidAccess();

        uint256 action;
        address user;
        (action, user, data) = abi.decode(data, (uint256, address, bytes));

        if (action == 0) {
            (OrderParams[] memory paramsList) = abi.decode(data, (OrderParams[]));
            uint256 length = paramsList.length;
            OrderId[] memory ids = new OrderId[](length);
            uint256 orderIdIndex;
            for (uint256 i = 0; i < length; ++i) {
                if (paramsList[i].makeOrderParams.maker != address(0)) {
                    ids[orderIdIndex++] = _make(user, paramsList[i].makeOrderParams);
                } else if (paramsList[i].spendOrderParams.recipient != address(0)) {
                    _take(user, paramsList[i].takeOrderParams);
                } else if (paramsList[i].takeOrderParams.recipient != address(0)) {
                    _spend(user, paramsList[i].spendOrderParams);
                } else if (OrderId.unwrap(paramsList[i].claimOrderParams.id) != 0) {
                    _claim(paramsList[i].claimOrderParams);
                } else if (OrderId.unwrap(paramsList[i].cancelOrderParams.id) != 0) {
                    _cancel(paramsList[i].cancelOrderParams);
                }
            }
            assembly {
                mstore(ids, orderIdIndex)
            }
            returnData = abi.encode(ids);
        } else if (action == 1) {
            (MakeOrderParams[] memory paramsList) = abi.decode(data, (MakeOrderParams[]));
            uint256 length = paramsList.length;
            OrderId[] memory ids = new OrderId[](length);
            for (uint256 i = 0; i < length; ++i) {
                ids[i] = _make(user, paramsList[i]);
            }
            returnData = abi.encode(ids);
        } else if (action == 2) {
            (TakeOrderParams[] memory paramsList) = abi.decode(data, (TakeOrderParams[]));
            uint256 length = paramsList.length;
            for (uint256 i = 0; i < length; ++i) {
                _take(user, paramsList[i]);
            }
        } else if (action == 3) {
            (SpendOrderParams[] memory paramsList) = abi.decode(data, (SpendOrderParams[]));
            uint256 length = paramsList.length;
            for (uint256 i = 0; i < length; ++i) {
                _spend(user, paramsList[i]);
            }
        }
    }

    function action(OrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
        returns (OrderId[] memory ids)
    {
        bytes memory lockData = abi.encode(0, msg.sender, abi.encode(paramsList));
        bytes memory result = _bookManager.lock(address(this), lockData);
        (ids) = abi.decode(result, (OrderId[]));
    }

    function make(MakeOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
        returns (OrderId[] memory ids)
    {
        bytes memory lockData = abi.encode(1, msg.sender, abi.encode(paramsList));
        bytes memory result = _bookManager.lock(address(this), lockData);
        (ids) = abi.decode(result, (OrderId[]));
    }

    function take(TakeOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
    {
        bytes memory lockData = abi.encode(2, msg.sender, abi.encode(paramsList));
        _bookManager.lock(address(this), lockData);
    }

    function spend(SpendOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        flushNative
        checkDeadline(deadline)
    {
        bytes memory lockData = abi.encode(3, msg.sender, abi.encode(paramsList));
        _bookManager.lock(address(this), lockData);
    }

    function claim(ClaimOrderParams[] calldata paramsList, uint64 deadline) external checkDeadline(deadline) {
        // claim bounty
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; ++i) {
            // Todo consider try catch
            _claim(paramsList[i]);
        }
    }

    function cancel(CancelOrderParams[] calldata paramsList, uint64 deadline) external checkDeadline(deadline) {
        // claim bounty
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; ++i) {
            // Todo consider try catch
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
                // Todo use safe toUint64
                amount: uint64(params.quoteAmount / key.unit),
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

        while (leftQuoteAmount > 0) {
            // Todo revert when book is empty
            (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                // Todo use safe toUint64
                IBookManager.TakeParams({key: key, maxAmount: uint64(leftQuoteAmount / key.unit)}),
                params.hookData
            );
            if (quoteAmount == 0) break;
            _bookManager.withdraw(key.quote, address(this), quoteAmount);

            unchecked {
                // Todo check underflow, overflow
                leftQuoteAmount -= quoteAmount;
                spendBaseAmount += baseAmount;
            }
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

        while (leftBaseAmount > 0) {
            // Todo revert when book is empty
            Tick tick = _bookManager.getRoot(params.id);
            (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                IBookManager.TakeParams({key: key, maxAmount: tick.baseToRaw(leftBaseAmount, false)}), params.hookData
            );
            if (quoteAmount == 0) break;
            _bookManager.withdraw(key.quote, address(this), quoteAmount);

            unchecked {
                // Todo check underflow, overflow
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

    function _claim(ClaimOrderParams calldata params) internal {
        _bookManager.claim(params.id, params.hookData);
    }

    function _cancel(CancelOrderParams calldata params) internal {
        (BookId bookId,,) = params.id.decode();
        _permitERC721(OrderId.unwrap(params.id), params.permitParams);
        _bookManager.cancel(
            // Todo use safe toUint64
            IBookManager.CancelParams({id: params.id, to: uint64(params.to / _bookManager.getBookKey(bookId).unit)}),
            params.hookData
        );
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
