// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IController} from "./interfaces/IController.sol";
import {ILocker} from "./interfaces/ILocker.sol";
import {IBookManager} from "./interfaces/IBookManager.sol";
import {IERC721Permit} from "./interfaces/IERC721Permit.sol";
import {Math} from "./libraries/Math.sol";
import {BookId, BookIdLibrary} from "./libraries/BookId.sol";
import {OrderId, OrderIdLibrary} from "./libraries/OrderId.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {FeePolicy, FeePolicyLibrary} from "./libraries/FeePolicy.sol";
import {Tick, TickLibrary} from "./libraries/Tick.sol";
import {OrderId, OrderIdLibrary} from "./libraries/OrderId.sol";

contract Controller is IController, ILocker, ReentrancyGuard {
    using TickLibrary for *;
    using OrderIdLibrary for OrderId;
    using BookIdLibrary for IBookManager.BookKey;
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using Math for uint256;
    using CurrencyLibrary for Currency;
    using FeePolicyLibrary for FeePolicy;

    IBookManager private immutable _bookManager;

    constructor(address bookManager) {
        _bookManager = IBookManager(bookManager);
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
        return uint256(_bookManager.getDepth(id, tick)) * _bookManager.getBookKey(id).unitSize;
    }

    function getHighestPrice(BookId id) external view returns (uint256) {
        return _bookManager.getHighest(id).toPrice();
    }

    function getOrder(OrderId orderId)
        external
        view
        returns (address provider, uint256 price, uint256 openAmount, uint256 claimableAmount)
    {
        (BookId bookId, Tick tick,) = orderId.decode();
        IBookManager.BookKey memory key = _bookManager.getBookKey(bookId);
        uint256 unitSize = key.unitSize;
        price = tick.toPrice();
        IBookManager.OrderInfo memory orderInfo = _bookManager.getOrder(orderId);
        provider = orderInfo.provider;
        openAmount = unitSize * orderInfo.open;
        FeePolicy makerPolicy = key.makerPolicy;
        claimableAmount = tick.quoteToBase(unitSize * orderInfo.claimable, false);
        if (!makerPolicy.usesQuote()) {
            int256 fee = makerPolicy.calculateFee(claimableAmount, false);
            claimableAmount = fee > 0 ? claimableAmount - uint256(fee) : claimableAmount + uint256(-fee);
        }
    }

    function fromPrice(uint256 price) external pure returns (Tick) {
        return price.fromPrice();
    }

    function toPrice(Tick tick) external pure returns (uint256) {
        return tick.toPrice();
    }

    function lockAcquired(address sender, bytes memory data) external nonReentrant returns (bytes memory returnData) {
        if (msg.sender != address(_bookManager) || sender != address(this)) revert InvalidAccess();
        (address user, Action[] memory actionList, bytes[] memory orderParamsList, address[] memory tokensToSettle) =
            abi.decode(data, (address, Action[], bytes[], address[]));

        uint256 length = actionList.length;
        OrderId[] memory ids = new OrderId[](length);
        uint256 orderIdIndex;

        for (uint256 i = 0; i < length; ++i) {
            Action action = actionList[i];
            if (action == Action.OPEN) {
                _open(abi.decode(orderParamsList[i], (OpenBookParams)));
            } else if (action == Action.MAKE) {
                OrderId id = _make(abi.decode(orderParamsList[i], (MakeOrderParams)));
                if (OrderId.unwrap(id) != 0) {
                    _bookManager.transferFrom(address(this), user, OrderId.unwrap(id));
                    ids[orderIdIndex++] = id;
                }
            } else if (action == Action.LIMIT) {
                OrderId id = _limit(abi.decode(orderParamsList[i], (LimitOrderParams)));
                if (OrderId.unwrap(id) != 0) {
                    _bookManager.transferFrom(address(this), user, OrderId.unwrap(id));
                    ids[orderIdIndex++] = id;
                }
            } else if (action == Action.TAKE) {
                _take(abi.decode(orderParamsList[i], (TakeOrderParams)));
            } else if (action == Action.SPEND) {
                _spend(abi.decode(orderParamsList[i], (SpendOrderParams)));
            } else if (action == Action.CLAIM) {
                ClaimOrderParams memory claimOrderParams = abi.decode(orderParamsList[i], (ClaimOrderParams));
                uint256 orderId = OrderId.unwrap(claimOrderParams.id);
                _bookManager.checkAuthorized(_bookManager.ownerOf(orderId), user, orderId);
                _claim(claimOrderParams);
            } else if (action == Action.CANCEL) {
                CancelOrderParams memory cancelOrderParams = abi.decode(orderParamsList[i], (CancelOrderParams));
                uint256 orderId = OrderId.unwrap(cancelOrderParams.id);
                _bookManager.checkAuthorized(_bookManager.ownerOf(orderId), user, orderId);
                _cancel(cancelOrderParams);
            } else {
                revert InvalidAction();
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

        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        bytes memory result = _bookManager.lock(address(this), lockData);

        if (result.length != 0) {
            (ids) = abi.decode(result, (OrderId[]));
        }
        return ids;
    }

    function open(OpenBookParams[] calldata openBookParamsList, uint64 deadline) external checkDeadline(deadline) {
        uint256 length = openBookParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.OPEN;
            paramsDataList[i] = abi.encode(openBookParamsList[i]);
        }
        address[] memory tokensToSettle;
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        _bookManager.lock(address(this), lockData);
    }

    function limit(
        LimitOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC20PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external payable checkDeadline(deadline) permitERC20(permitParamsList) returns (OrderId[] memory ids) {
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.LIMIT;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        bytes memory result = _bookManager.lock(address(this), lockData);
        (ids) = abi.decode(result, (OrderId[]));
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

    function claim(
        ClaimOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC721PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external checkDeadline(deadline) {
        _permitERC721(permitParamsList);
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.CLAIM;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        _bookManager.lock(address(this), lockData);
    }

    function cancel(
        CancelOrderParams[] calldata orderParamsList,
        address[] calldata tokensToSettle,
        ERC721PermitParams[] calldata permitParamsList,
        uint64 deadline
    ) external checkDeadline(deadline) {
        _permitERC721(permitParamsList);
        uint256 length = orderParamsList.length;
        Action[] memory actionList = new Action[](length);
        bytes[] memory paramsDataList = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            actionList[i] = Action.CANCEL;
            paramsDataList[i] = abi.encode(orderParamsList[i]);
        }
        bytes memory lockData = abi.encode(msg.sender, actionList, paramsDataList, tokensToSettle);
        _bookManager.lock(address(this), lockData);
    }

    function _open(OpenBookParams memory params) internal {
        _bookManager.open(params.key, params.hookData);
    }

    function _make(MakeOrderParams memory params) internal returns (OrderId id) {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

        uint256 quoteAmount = params.quoteAmount;
        if (key.makerPolicy.usesQuote()) {
            quoteAmount = key.makerPolicy.calculateOriginalAmount(quoteAmount, false);
        }
        uint64 unit = (quoteAmount / key.unitSize).toUint64();
        if (unit > 0) {
            (id,) = _bookManager.make(
                IBookManager.MakeParams({key: key, tick: params.tick, unit: unit, provider: address(0)}),
                params.hookData
            );
        }
        return id;
    }

    function _limit(LimitOrderParams memory params) internal returns (OrderId id) {
        (, uint256 spentBaseAmount) = _spend(
            SpendOrderParams({
                id: params.takeBookId,
                limitPrice: params.limitPrice,
                baseAmount: params.quoteAmount,
                minQuoteAmount: 0,
                hookData: params.takeHookData
            })
        );
        params.quoteAmount -= spentBaseAmount;
        if (params.quoteAmount > 0) {
            id = _make(
                MakeOrderParams({
                    id: params.makeBookId,
                    quoteAmount: params.quoteAmount,
                    tick: params.tick,
                    hookData: params.makeHookData
                })
            );
        }
    }

    function _take(TakeOrderParams memory params)
        internal
        returns (uint256 takenQuoteAmount, uint256 spentBaseAmount)
    {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

        while (params.quoteAmount > takenQuoteAmount && !_bookManager.isEmpty(params.id)) {
            Tick tick = _bookManager.getHighest(params.id);
            if (params.limitPrice > tick.toPrice()) break;
            uint256 maxAmount;
            unchecked {
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = key.takerPolicy.calculateOriginalAmount(params.quoteAmount - takenQuoteAmount, true);
                } else {
                    maxAmount = params.quoteAmount - takenQuoteAmount;
                }
            }
            maxAmount = maxAmount.divide(key.unitSize, true);

            if (maxAmount == 0) break;
            (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                IBookManager.TakeParams({key: key, tick: tick, maxUnit: maxAmount.toUint64()}), params.hookData
            );
            if (quoteAmount == 0) break;

            takenQuoteAmount += quoteAmount;
            spentBaseAmount += baseAmount;
        }
        if (params.maxBaseAmount < spentBaseAmount) revert ControllerSlippage();
    }

    function _spend(SpendOrderParams memory params)
        internal
        returns (uint256 takenQuoteAmount, uint256 spentBaseAmount)
    {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id);

        while (spentBaseAmount < params.baseAmount && !_bookManager.isEmpty(params.id)) {
            Tick tick = _bookManager.getHighest(params.id);
            if (params.limitPrice > tick.toPrice()) break;
            uint256 maxAmount;
            unchecked {
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = params.baseAmount - spentBaseAmount;
                } else {
                    maxAmount = key.takerPolicy.calculateOriginalAmount(params.baseAmount - spentBaseAmount, false);
                }
            }
            maxAmount = tick.baseToQuote(maxAmount, false) / key.unitSize;
            if (maxAmount == 0) break;
            (uint256 quoteAmount, uint256 baseAmount) = _bookManager.take(
                IBookManager.TakeParams({key: key, tick: tick, maxUnit: maxAmount.toUint64()}), params.hookData
            );
            if (baseAmount == 0) break;
            takenQuoteAmount += quoteAmount;
            spentBaseAmount += baseAmount;
        }
        if (params.minQuoteAmount > takenQuoteAmount) revert ControllerSlippage();
    }

    function _claim(ClaimOrderParams memory params) internal {
        _bookManager.claim(params.id, params.hookData);
    }

    function _cancel(CancelOrderParams memory params) internal {
        IBookManager.BookKey memory key = _bookManager.getBookKey(params.id.getBookId());
        try _bookManager.cancel(
            IBookManager.CancelParams({id: params.id, toUnit: (params.leftQuoteAmount / key.unitSize).toUint64()}),
            params.hookData
        ) {} catch {}
    }

    function _settleTokens(address user, address[] memory tokensToSettle) internal {
        Currency native = CurrencyLibrary.NATIVE;
        int256 currencyDelta = _bookManager.currencyDelta(address(this), native);
        if (currencyDelta < 0) {
            native.transfer(address(_bookManager), uint256(-currencyDelta));
            _bookManager.settle(native);
        }
        currencyDelta = _bookManager.currencyDelta(address(this), native);
        if (currencyDelta > 0) {
            _bookManager.withdraw(native, user, uint256(currencyDelta));
        }

        uint256 length = tokensToSettle.length;
        for (uint256 i = 0; i < length; ++i) {
            Currency currency = Currency.wrap(tokensToSettle[i]);
            currencyDelta = _bookManager.currencyDelta(address(this), currency);
            if (currencyDelta < 0) {
                IERC20(tokensToSettle[i]).safeTransferFrom(user, address(_bookManager), uint256(-currencyDelta));
                _bookManager.settle(currency);
            }
            currencyDelta = _bookManager.currencyDelta(address(this), currency);
            if (currencyDelta > 0) {
                _bookManager.withdraw(Currency.wrap(tokensToSettle[i]), user, uint256(currencyDelta));
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
                    address(this),
                    permitParamsList[i].tokenId,
                    signature.deadline,
                    signature.v,
                    signature.r,
                    signature.s
                ) {} catch {}
            }
        }
    }

    receive() external payable {}
}
