// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./libraries/BookId.sol";
import "./libraries/Book.sol";
import "./libraries/OrderId.sol";
import "./libraries/LockData.sol";
import "./interfaces/IPositionLocker.sol";

contract BookManager is IBookManager, Ownable {
    using SafeCast for *;
    using BookIdLibrary for IBookManager.BookKey;
    using TickLibrary for Tick;
    using Book for Book.State;
    using OrderIdLibrary for OrderId;
    using LockDataLibrary for LockData;
    using CurrencyLibrary for Currency;

    int256 private constant _RATE_PRECISION = 10 ** 6;

    address public override defaultProvider;
    LockData public override lockData;

    mapping(address locker => mapping(Currency currency => int256 currencyDelta)) public override currencyDelta;
    mapping(Currency currency => uint256) public override reservesOf;
    mapping(BookId id => Book.State) internal _books;
    mapping(OrderId => Order) internal _orders;
    mapping(address provider => bool) public override isWhitelisted;
    mapping(address provider => mapping(Currency currency => uint256 amount)) public override tokenOwed;

    constructor(address defaultProvider_) {
        setDefaultProvider(defaultProvider_);
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

    function _accountDelta(Currency currency, int256 delta) internal {
        if (delta == 0) return;

        address locker = lockData.getActiveLock();
        int256 current = currencyDelta[locker][currency];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                lockData.nonzeroDeltaCount--;
            } else if (current == 0) {
                lockData.nonzeroDeltaCount++;
            }
        }

        currencyDelta[locker][currency] = next;
    }

    function _getBook(BookKey memory key) private view returns (Book.State storage) {
        return _books[key.toId()];
    }

    function getBookKey(BookId id) external view returns (BookKey memory) {
        return _books[id].key;
    }

    function getOrder(OrderId id) external view returns (Order memory) {
        return _orders[id];
    }

    function make(IBookManager.MakeParams[] calldata paramsList) external onlyByLocker returns (OrderId[] memory ids) {
        ids = new OrderId[](paramsList.length);
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.MakeParams calldata params = paramsList[i];
            if (params.provider != address(0) && !isWhitelisted[params.provider]) {
                revert NotWhitelisted(params.provider);
            }
            Book.State storage book = _getBook(params.key);
            ids[i] = book.make(
                _orders, params.key.toId(), params.user, params.tick, params.amount, params.provider, params.bounty
            );
            uint256 quoteAmount = uint256(params.amount) * params.key.unitDecimals;
            if (!params.key.makerPolicy.useOutput) {
                (quoteAmount,) = _calculateFee(quoteAmount, params.key.makerPolicy.rate);
            }
            _accountDelta(params.key.quote, quoteAmount.toInt256());
        }
    }

    function take(IBookManager.TakeParams[] calldata paramsList) external onlyByLocker {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.TakeParams calldata params = paramsList[i];
            Book.State storage book = _getBook(params.key);
            BookId bookId = params.key.toId();
            (uint256 baseAmount, uint256 quoteAmount) = book.take(bookId, msg.sender, params.amount, params.limit);
            quoteAmount *= params.key.unitDecimals;
            if (params.key.takerPolicy.useOutput) {
                (quoteAmount,) = _calculateFee(quoteAmount, params.key.takerPolicy.rate);
            } else {
                (baseAmount,) = _calculateFee(baseAmount, params.key.takerPolicy.rate);
            }
            if (baseAmount > params.maxIn) {
                revert Slippage(bookId);
            }
            _accountDelta(params.key.quote, -quoteAmount.toInt256());
            _accountDelta(params.key.base, baseAmount.toInt256());
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
                // todo: reverse calculation
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
            _accountDelta(params.key.quote, -quoteAmount.toInt256());
            _accountDelta(params.key.base, baseAmount.toInt256());
        }
    }

    function reduce(IBookManager.ReduceParams[] calldata paramsList) external onlyByLocker {
        for (uint256 i = 0; i < paramsList.length; ++i) {
            IBookManager.ReduceParams calldata params = paramsList[i];
            (BookId bookId,,) = params.id.decode();
            uint256 reducedAmount = _books[bookId].reduce(params.id, _orders[params.id], params.to);
            reducedAmount *= _books[bookId].key.unitDecimals;
            int256 fee;
            FeePolicy memory makerPolicy = _books[bookId].key.makerPolicy;
            if (!makerPolicy.useOutput) {
                // todo: reverse calculation
            }
            _accountDelta(_books[bookId].key.quote, -reducedAmount.toInt256());
        }
    }

    function cancel(OrderId[] calldata ids) external onlyByLocker {
        for (uint256 i = 0; i < ids.length; ++i) {
            OrderId id = ids[i];
            (BookId bookId,,) = id.decode();
            Book.State storage book = _books[bookId];
            uint256 canceledAmount = book.cancel(id, _orders[id]);
            canceledAmount *= _books[bookId].key.unitDecimals;
            int256 fee;
            FeePolicy memory makerPolicy = _books[bookId].key.makerPolicy;
            if (!makerPolicy.useOutput) {
                // todo: reverse calculation
            }
            _accountDelta(_books[bookId].key.quote, -canceledAmount.toInt256());
        }
    }

    function claim(OrderId[] calldata ids) external onlyByLocker {
        for (uint256 i = 0; i < ids.length; ++i) {
            OrderId id = ids[i];
            (BookId bookId,,) = id.decode();
            Book.State storage book = _books[bookId];
            IBookManager.BookKey memory bookKey = book.key;
            Order storage order = _orders[id];
            (uint256 claimedInQuote, uint256 claimedInBase) = book.claim(id, order);
            claimedInQuote *= bookKey.unitDecimals;
            int256 quoteFee;
            int256 baseFee;
            FeePolicy memory takerPolicy = bookKey.takerPolicy;
            FeePolicy memory makerPolicy = bookKey.makerPolicy;
            if (takerPolicy.useOutput) {
                (, quoteFee) = _calculateFee(claimedInQuote, takerPolicy.rate);
            } else {
                (, baseFee) = _calculateFee(claimedInBase, takerPolicy.rate);
            }
            if (makerPolicy.useOutput) {
                int256 makerFee;
                (claimedInBase, makerFee) = _calculateFee(claimedInBase, makerPolicy.rate);
                baseFee += makerFee;
                _accountDelta(bookKey.base, -claimedInBase.toInt256());
            } else {
                int256 makerFee;
                (, makerFee) = _calculateFee(claimedInQuote, makerPolicy.rate);
                quoteFee += makerFee;
            }

            address provider = order.provider;
            if (provider == address(0)) {
                provider = defaultProvider;
            }
            tokenOwed[provider][bookKey.quote] += quoteFee.toUint256();
            tokenOwed[provider][bookKey.base] += baseFee.toUint256();
        }
    }

    function collect(address provider, Currency currency) external {
        uint256 amount = tokenOwed[provider][currency];
        if (amount > 0) {
            tokenOwed[provider][currency] = 0;
            currency.transfer(provider, amount);
            emit Collect(provider, currency, amount);
        }
    }

    function whitelist(address[] calldata providers) external onlyOwner {
        unchecked {
            for (uint256 i = 0; i < providers.length; ++i) {
                _whitelist(providers[i]);
            }
        }
    }

    function delist(address[] calldata providers) external onlyOwner {
        unchecked {
            for (uint256 i = 0; i < providers.length; ++i) {
                _delist(providers[i]);
            }
        }
    }

    function setDefaultProvider(address newDefaultProvider) public onlyOwner {
        address oldDefaultProvider = defaultProvider;
        defaultProvider = newDefaultProvider;
        _delist(oldDefaultProvider);
        _whitelist(newDefaultProvider);
        emit SetDefaultProvider(oldDefaultProvider, newDefaultProvider);
    }

    function _whitelist(address provider) internal {
        isWhitelisted[provider] = true;
        emit Whitelist(provider);
    }

    function _delist(address provider) internal {
        isWhitelisted[provider] = false;
        emit Delist(provider);
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
