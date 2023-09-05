// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./libraries/BookId.sol";
import "./libraries/Book.sol";
import "./libraries/OrderId.sol";
import "./libraries/LockData.sol";
import "./interfaces/IPositionLocker.sol";

contract BookManager is IBookManager, Ownable {
    using BookIdLibrary for IBookManager.BookKey;
    using TickLibrary for Tick;
    using Book for Book.State;
    using OrderIdLibrary for OrderId;
    using LockDataLibrary for LockData;
    using CurrencyLibrary for Currency;

    int256 private constant _RATE_PRECISION = 10 ** 6;

    address public override treasury;
    LockData public override lockData;

    mapping(address locker => mapping(Currency currency => int256 currencyDelta)) public override currencyDelta;
    mapping(Currency currency => uint256) public override reservesOf;
    mapping(BookId id => Book.State) internal _books;
    mapping(address provider => bool) public override isWhitelisted;
    // TODO: Check if user can has below state. If not, change user to provider.
    mapping(address user => mapping(Currency currency => uint256 amount)) public override tokenOwed;

    constructor(address treasury_) {
        setTreasury(treasury_);
    }

    modifier onlyByLocker() {
        address locker = lockData.getActiveLock();
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    function lock(bytes calldata data) external returns (bytes memory result) {
        lockData.push(msg.sender);

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILocker(msg.sender).lockAcquired(data);

        if (lockData.length == 1) {
            if (lockData.nonzeroDeltaCount != 0) revert CurrencyNotSettled();
            delete lockData;
        } else {
            lockData.pop();
        }
    }

    function _getBook(BookKey memory key) private view returns (Book.State storage) {
        return _books[key.toId()];
    }

    function getBookKey(BookId id) external view returns (BookKey memory) {
        return _books[id].key;
    }

    function getOrder(OrderId id) external view returns (Book.Order memory) {
        (BookId bookId,,) = id.decode();
        return _books[bookId].orders[id];
    }

    function make(IBookManager.MakeParams[] calldata paramsList) external onlyByLocker returns (OrderId[] memory ids) {
        ids = new OrderId[](paramsList.length);
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.MakeParams calldata params = paramsList[i];
            if (params.provider != address(0) && !isWhitelisted[params.provider]) {
                revert NotWhitelisted(params.provider);
            }
            Book.State storage book = _getBook(params.key);
            int256 fee;
            ids[i] =
                book.make(params.key.toId(), params.user, params.tick, params.amount, params.provider, params.bounty);
            uint256 quoteAmount = uint256(params.amount) * params.key.unitDecimals;
            if (!params.key.makerPolicy.useOutput) {
                (quoteAmount, fee) = _calculateFee(quoteAmount, params.key.makerPolicy.rate);
            }
        }
    }

    function take(IBookManager.TakeParams[] calldata paramsList) external onlyByLocker {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.TakeParams calldata params = paramsList[i];
            Book.State storage book = _getBook(params.key);
            BookId bookId = params.key.toId();
            (uint256 baseAmount, uint256 quoteAmount) = book.take(bookId, msg.sender, params.amount, params.limit);
            quoteAmount *= params.key.unitDecimals;
            int256 fee;
            if (params.key.takerPolicy.useOutput) {
                (quoteAmount, fee) = _calculateFee(quoteAmount, params.key.takerPolicy.rate);
            } else {
                (baseAmount, fee) = _calculateFee(baseAmount, params.key.takerPolicy.rate);
            }
            if (baseAmount > params.maxIn) {
                revert Slippage(bookId);
            }
            // todo: account delta
        }
    }

    function spend(IBookManager.SpendParams[] calldata paramsList) external onlyByLocker {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.SpendParams calldata params = paramsList[i];
            Book.State storage book = _getBook(params.key);
            BookId bookId = params.key.toId();
            uint256 amountToRequest = params.amount;
            int256 fee;
            if (!params.key.takerPolicy.useOutput) {
                (amountToRequest, fee) = _calculateFee(amountToRequest, params.key.takerPolicy.rate);
            }
            (uint256 baseAmount, uint256 quoteAmount) = book.spend(bookId, msg.sender, amountToRequest, params.limit);
            quoteAmount *= params.key.unitDecimals;
            if (params.key.takerPolicy.useOutput) {
                (quoteAmount, fee) = _calculateFee(quoteAmount, params.key.takerPolicy.rate);
            }
            if (quoteAmount < params.minOut) {
                revert Slippage(bookId);
            }
            // todo: account delta
        }
    }

    function reduce(IBookManager.ReduceParams[] calldata paramsList) external onlyByLocker {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.ReduceParams calldata params = paramsList[i];
            (BookId bookId,,) = params.id.decode();
            uint256 reducedAmount = _books[bookId].reduce(params.id, params.to);
            reducedAmount *= _books[bookId].key.unitDecimals;
            int256 fee;
            FeePolicy memory makerPolicy = _books[bookId].key.makerPolicy;
            if (!makerPolicy.useOutput) {
                // todo: reverse calculation
            }
            // todo: account delta
        }
    }

    function cancel(OrderId[] calldata ids) external onlyByLocker {
        for (uint256 i = 0; i < ids.length; ++i) {
            OrderId id = ids[i];
            (BookId bookId,,) = id.decode();
            Book.State storage book = _books[bookId];
            uint256 canceledAmount = book.cancel(id);
            canceledAmount *= _books[bookId].key.unitDecimals;
            int256 fee;
            FeePolicy memory makerPolicy = _books[bookId].key.makerPolicy;
            if (!makerPolicy.useOutput) {
                // todo: reverse calculation
            }
            // todo: account delta
        }
    }

    function claim(OrderId[] calldata ids) external onlyByLocker {
        for (uint256 i = 0; i < ids.length; ++i) {
            OrderId id = ids[i];
            (BookId bookId,,) = id.decode();
            Book.State storage book = _books[bookId];
            (uint64 claimedRaw, uint256 claimedAmount, address provider) = book.claim(id);
            int256 fee;
            FeePolicy memory makerPolicy = _books[bookId].key.makerPolicy;
            if (makerPolicy.useOutput) {
                (claimedAmount, fee) = _calculateFee(claimedAmount, makerPolicy.rate);
                // todo: account delta
            } else {
                (, fee) = _calculateFee(uint256(claimedRaw) * _books[bookId].key.unitDecimals, makerPolicy.rate);
            }
            // todo: also calculate taker fee and store it
        }
    }

    function collect(address provider, Currency currency) external {
        uint256 amount = tokenOwed[provider][currency];
        if (amount > 0) {
            tokenOwed[provider][currency] = 0;
            currency.transfer(provider, amount);
            // todo: event
        }
    }

    function whitelist(address[] calldata providers) external onlyOwner {
        unchecked {
            for (uint256 i = 0; i < providers.length; ++i) {
                isWhitelisted[providers[i]] = true;
            }
        }
    }

    function delist(address[] calldata providers) external onlyOwner {
        unchecked {
            for (uint256 i = 0; i < providers.length; ++i) {
                isWhitelisted[providers[i]] = false;
            }
        }
    }

    function setTreasury(address newTreasury) public onlyOwner {
        emit SetTreasury(treasury, newTreasury);
        treasury = newTreasury;
    }

    function _calculateFee(uint256 amount, int24 rate) internal pure returns (uint256 adjustedAmount, int256 fee) {
        if (rate > 0) {
            fee = int256(Math.divide(amount * uint24(rate), uint256(_RATE_PRECISION), true));
            adjustedAmount = amount - uint256(fee);
        } else {
            fee = -int256(Math.divide(amount * uint24(-rate), uint256(_RATE_PRECISION), false));
            adjustedAmount = amount + uint256(-fee);
        }
    }
}
