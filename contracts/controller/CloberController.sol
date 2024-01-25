// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/ICloberController.sol";
import "../interfaces/IPositionLocker.sol";
import "../interfaces/IBookManager.sol";
import "../libraries/OrderId.sol";

contract CloberController is ICloberController, IPositionLocker {
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
        if (block.timestamp > deadline) {
            revert Deadline();
        }
        _;
    }

    function positionLockAcquired(bytes memory data) external returns (bytes memory result) {
        if (msg.sender != address(_bookManager)) revert InvalidAccess();

        uint256 action;
        (action, data) = abi.decode(data, (uint256, bytes));

        if (action == 0) {
            (MakeOrderParams[] memory paramsList) = abi.decode(data, (MakeOrderParams[]));
            OrderId[] memory ids = _make(paramsList);
            result = abi.encode(ids);
        } else if (action == 1) {
            (TakeOrderParams[] memory paramsList) = abi.decode(data, (TakeOrderParams[]));
            _take(paramsList);
        } else if (action == 2) {
            (SpendOrderParams[] memory paramsList) = abi.decode(data, (SpendOrderParams[]));
            _spend(paramsList);
        }
    }

    function make(MakeOrderParams[] calldata paramsList, uint64 deadline)
        external
        payable
        returns (OrderId[] memory ids)
    {
        bytes memory lockData = abi.encode(0, abi.encode(paramsList));
        bytes memory result = _bookManager.lock(address(this), lockData);
        (ids) = abi.decode(result, (OrderId[]));
    }

    function take(TakeOrderParams[] calldata paramsList, uint64 deadline) external payable checkDeadline(deadline) {
        bytes memory lockData = abi.encode(1, abi.encode(paramsList));
        _bookManager.lock(address(this), lockData);
    }

    function spend(SpendOrderParams[] calldata paramsList, uint64 deadline) external payable checkDeadline(deadline) {
        bytes memory lockData = abi.encode(2, abi.encode(paramsList));
        _bookManager.lock(address(this), lockData);
    }

    function claim(ClaimOrderParams[] calldata paramsList, uint64 deadline) external checkDeadline(deadline) {
        // claim bounty
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; i++) {
            // Todo consider try catch
            ClaimOrderParams memory params = paramsList[i];
            _bookManager.claim(params.id, params.hookData);
        }
    }

    function cancel(CancelOrderParams[] calldata paramsList, uint64 deadline) external checkDeadline(deadline) {
        // claim bounty
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; i++) {
            // Todo consider try catch
            CancelOrderParams memory params = paramsList[i];
            (BookId bookId,,) = params.id.decode();
            _permitERC721(OrderId.unwrap(params.id), params.permitParams);
            _bookManager.cancel(
                // Todo use safe toUint64
                IBookManager.CancelParams({id: params.id, to: uint64(params.to / _bookManager.getBookKey(bookId).unit)}),
                params.hookData
            );
        }
    }

    function _make(MakeOrderParams[] memory paramsList) internal returns (OrderId[] memory ids) {
        uint256 length = paramsList.length;
        ids = new OrderId[](length);
        for (uint256 i = 0; i < length; i++) {
            MakeOrderParams memory params = paramsList[i];
            Tick tick = params.price.fromPrice();
            IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);
            _permitERC20(Currency.unwrap(key.quote), params.permitParams);
            uint256 quoteAmount;
            (ids[i], quoteAmount) = _bookManager.make(
                IBookManager.MakeParams({
                    key: key,
                    tick: tick,
                    // Todo use safe toUint64
                    amount: uint64(params.quoteAmount / key.unit),
                    provider: _provider
                }),
                params.hookData
            );
            key.quote.transfer(address(_bookManager), quoteAmount);
            _bookManager.settle(key.quote);
        }
    }

    function _take(TakeOrderParams[] memory paramsList) internal {
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; i++) {
            TakeOrderParams memory params = paramsList[i];
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
            IERC20(Currency.unwrap(key.base)).safeTransferFrom(msg.sender, address(_bookManager), spendBaseAmount);
            _bookManager.settle(key.base);
        }
    }

    function _spend(SpendOrderParams[] memory paramsList) internal {
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; i++) {
            SpendOrderParams memory params = paramsList[i];
            IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

            uint256 takenQuoteAmount;
            uint256 leftBaseAmount = params.baseAmount;

            while (leftBaseAmount > 0) {
                // Todo revert when book is empty
                Tick tick = _bookManager.getRoot(params.id);
                (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                    IBookManager.TakeParams({key: key, maxAmount: tick.baseToRaw(leftBaseAmount, false)}),
                    params.hookData
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
            unchecked {
                IERC20(Currency.unwrap(key.base)).safeTransferFrom(
                    msg.sender, address(_bookManager), params.baseAmount - leftBaseAmount
                );
            }
            _bookManager.settle(key.base);
        }
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
