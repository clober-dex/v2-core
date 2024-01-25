// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./libraries/BookId.sol";
import "./libraries/Book.sol";
import "./libraries/OrderId.sol";
import "./libraries/Lockers.sol";
import "./interfaces/ILocker.sol";
import "./libraries/ERC721Permit.sol";
import "./libraries/Hooks.sol";

contract BookManager is IBookManager, Ownable2Step, ERC721Permit {
    using SafeCast for *;
    using BookIdLibrary for IBookManager.BookKey;
    using TickLibrary for Tick;
    using Book for Book.State;
    using OrderIdLibrary for OrderId;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    int256 private constant _RATE_PRECISION = 10 ** 6;
    int256 private constant _MAX_FEE_RATE = 10 ** 6 / 2;
    int256 private constant _MIN_FEE_RATE = -(10 ** 6 / 2);

    string public override baseURI;
    address public override defaultProvider;

    mapping(address locker => mapping(Currency currency => int256 currencyDelta)) public override currencyDelta;
    mapping(Currency currency => uint256) public override reservesOf;
    mapping(BookId id => Book.State) internal _books;
    mapping(OrderId => Order) internal _orders;
    mapping(address provider => bool) public override isWhitelisted;
    mapping(address provider => mapping(Currency currency => uint256 amount)) public override tokenOwed;

    constructor(
        address owner_,
        address defaultProvider_,
        string memory baseURI_,
        string memory name_,
        string memory symbol_
    ) Ownable(owner_) ERC721Permit(name_, symbol_, "2") {
        setDefaultProvider(defaultProvider_);
        baseURI = baseURI_;
        Lockers.initialize();
    }

    modifier onlyByLocker() {
        _checkLocker(msg.sender);
        _;
    }

    function _checkLocker(address caller) internal view {
        address locker = Lockers.getCurrentLocker();
        IHooks hook = Lockers.getCurrentHook();
        if (caller == locker) return;
        if (caller == address(hook) && hook.hasPermission(Hooks.ACCESS_LOCK_FLAG)) return;
        revert LockedBy(locker, address(hook));
    }

    function nonces(uint256 id) external view returns (uint256) {
        return _orders[OrderId.wrap(id)].nonce;
    }

    function getBookKey(BookId id) external view returns (BookKey memory) {
        return _books[id].key;
    }

    function getOrder(OrderId id) external view returns (Order memory) {
        return _orders[id];
    }

    function open(BookKey calldata key, bytes calldata hookData) external {
        if (key.unit == 0) revert InvalidUnit();

        if (
            key.makerPolicy.rate > _MAX_FEE_RATE || key.takerPolicy.rate > _MAX_FEE_RATE
                || key.makerPolicy.rate < _MIN_FEE_RATE || key.takerPolicy.rate < _MIN_FEE_RATE
        ) {
            revert InvalidFeePolicy();
        }
        unchecked {
            if (key.makerPolicy.rate + key.takerPolicy.rate < 0) revert InvalidFeePolicy();
        }
        if (key.makerPolicy.rate < 0 || key.takerPolicy.rate < 0) {
            if (key.makerPolicy.useOutput == key.takerPolicy.useOutput) revert InvalidFeePolicy();
        }
        if (!key.hooks.isValidHookAddress()) revert Hooks.HookAddressNotValid(address(key.hooks));

        key.hooks.beforeOpen(key, hookData);

        BookId id = key.toId();
        _books[id].open(key);

        key.hooks.afterOpen(key, hookData);

        emit Open(id, key.base, key.quote, key.unit, key.makerPolicy, key.takerPolicy, key.hooks);
    }

    function lock(address locker, bytes calldata data) external returns (bytes memory result) {
        Lockers.push(locker, msg.sender);

        // the locker does everything in this callback, including paying what they owe via calls to settle
        result = ILocker(locker).lockAcquired(msg.sender, data);

        (uint128 length, uint128 nonzeroDeltaCount) = Lockers.lockData();
        if (length == 1) {
            if (nonzeroDeltaCount != 0) revert CurrencyNotSettled();
            Lockers.clear();
        } else {
            Lockers.pop();
        }
    }

    function getLock(uint256 i) external view returns (address, address) {
        return (Lockers.getLocker(i), Lockers.getLockCaller(i));
    }

    function getLockData() external view returns (uint128, uint128) {
        return Lockers.lockData();
    }

    function getDepth(BookId id, Tick tick) external view returns (uint64) {
        return _books[id].depth(tick);
    }

    function getRoot(BookId id) external view returns (Tick) {
        return _books[id].root();
    }

    function isEmpty(BookId id) external view returns (bool) {
        return _books[id].isEmpty();
    }

    function make(MakeParams calldata params, bytes calldata hookData)
        external
        onlyByLocker
        returns (OrderId id, uint256 quoteAmount)
    {
        if (params.provider != address(0) && !isWhitelisted[params.provider]) revert NotWhitelisted(params.provider);
        params.tick.validate();
        BookId bookId = params.key.toId();
        Book.State storage book = _books[bookId];
        book.checkOpened();

        if (!params.key.hooks.beforeMake(params, hookData)) return (OrderId.wrap(0), 0);

        uint40 orderIndex = book.make(_orders, bookId, params.tick, params.amount);
        id = OrderIdLibrary.encode(bookId, params.tick, orderIndex);
        unchecked {
            // @dev uint64 * uint96 < type(uint256).max
            quoteAmount = uint256(params.amount) * params.key.unit;
        }
        int256 quoteDelta = quoteAmount.toInt256();
        if (!params.key.makerPolicy.useOutput) {
            quoteDelta -= _calculateFee(quoteAmount, params.key.makerPolicy.rate);
        }
        _accountDelta(params.key.quote, quoteDelta);

        _mint(msg.sender, OrderId.unwrap(id));
        Order storage order = _orders[id];
        order.initial = params.amount;
        order.pending = params.amount;
        order.provider = params.provider;

        params.key.hooks.afterMake(params, id, hookData);

        emit Make(bookId, msg.sender, params.amount, orderIndex, params.tick);
    }

    function take(TakeParams calldata params, bytes calldata hookData)
        external
        onlyByLocker
        returns (uint256 quoteAmount, uint256 baseAmount)
    {
        BookId bookId = params.key.toId();
        Book.State storage book = _books[bookId];
        book.checkOpened();

        if (!params.key.hooks.beforeTake(params, hookData)) return (0, 0);

        (Tick tick, uint64 takenAmount) = book.take(params.maxAmount);
        baseAmount = tick.rawToBase(takenAmount, true);
        unchecked {
            quoteAmount = uint256(takenAmount) * params.key.unit;
        }

        {
            int256 quoteDelta = quoteAmount.toInt256();
            int256 baseDelta = baseAmount.toInt256();
            if (params.key.takerPolicy.useOutput) {
                quoteDelta -= _calculateFee(quoteAmount, params.key.takerPolicy.rate);
            } else {
                baseDelta -= _calculateFee(baseAmount, params.key.takerPolicy.rate);
            }
            _accountDelta(params.key.quote, -quoteDelta);
            _accountDelta(params.key.base, baseDelta);
        }

        params.key.hooks.afterTake(params, tick, takenAmount, hookData);

        emit Take(bookId, msg.sender, tick, takenAmount);
    }

    function cancel(CancelParams calldata params, bytes calldata hookData) external {
        Order storage order = _orders[params.id];
        address owner = order.owner;
        _checkAuthorized(owner, msg.sender, OrderId.unwrap(params.id));

        Book.State storage book;
        (BookId bookId,,) = params.id.decode();
        book = _books[bookId];

        BookKey memory key = book.key;
        book.checkOpened();

        if (!key.hooks.beforeCancel(params, hookData)) return;

        uint64 canceledRaw = book.cancel(params.id, order, params.to);

        uint256 canceledAmount;
        unchecked {
            canceledAmount = uint256(canceledRaw) * key.unit;
        }
        FeePolicy memory makerPolicy = key.makerPolicy;
        if (!makerPolicy.useOutput) {
            canceledAmount = _calculateAmountInReverse(canceledAmount, makerPolicy.rate);
        }
        key.quote.transfer(owner, canceledAmount);

        if (order.pending == 0) _burn(OrderId.unwrap(params.id));

        key.hooks.afterCancel(params, canceledRaw, hookData);

        emit Cancel(params.id, canceledRaw);
    }

    function claim(OrderId id, bytes calldata hookData) external {
        Tick tick;
        uint40 orderIndex;
        Book.State storage book;
        {
            BookId bookId;
            (bookId, tick, orderIndex) = id.decode();
            book = _books[bookId];
        }
        book.checkOpened();
        IBookManager.BookKey memory key = book.key;
        Order storage order = _orders[id];

        uint64 claimableRaw = book.calculateClaimableRawAmount(order.pending, tick, orderIndex);
        if (claimableRaw == 0) return;

        if (!key.hooks.beforeClaim(id, hookData)) return;

        unchecked {
            order.pending -= claimableRaw;
        }

        uint256 claimableAmount;
        int256 quoteFee;
        int256 baseFee;
        {
            claimableAmount = tick.rawToBase(claimableRaw, false);
            uint256 claimedInQuote;
            unchecked {
                claimedInQuote = uint256(claimableRaw) * key.unit;
            }
            FeePolicy memory makerPolicy = key.makerPolicy;
            FeePolicy memory takerPolicy = key.takerPolicy;
            if (takerPolicy.useOutput) {
                quoteFee = _calculateFee(claimedInQuote, takerPolicy.rate);
            } else {
                baseFee = _calculateFee(claimableAmount, takerPolicy.rate);
            }
            if (makerPolicy.useOutput) {
                int256 makerFee = _calculateFee(claimableAmount, makerPolicy.rate);
                claimableAmount =
                    makerFee > 0 ? claimableAmount - uint256(makerFee) : claimableAmount + uint256(-makerFee);
                baseFee += makerFee;
            } else {
                quoteFee += _calculateFee(claimedInQuote, makerPolicy.rate);
            }
        }

        address provider = order.provider;
        if (provider == address(0)) provider = defaultProvider;
        tokenOwed[provider][key.quote] += quoteFee.toUint256();
        tokenOwed[provider][key.base] += baseFee.toUint256();

        if (order.pending == 0) _burn(OrderId.unwrap(id));

        key.base.transfer(order.owner, claimableAmount);

        key.hooks.afterClaim(id, claimableRaw, hookData);

        emit Claim(msg.sender, id, claimableRaw);
    }

    function collect(address provider, Currency currency) external {
        uint256 amount = tokenOwed[provider][currency];
        if (amount > 0) {
            tokenOwed[provider][currency] = 0;
            currency.transfer(provider, amount);
            emit Collect(provider, currency, amount);
        }
    }

    function withdraw(Currency currency, address to, uint256 amount) external onlyByLocker {
        if (amount > 0) {
            _accountDelta(currency, amount.toInt256());
            reservesOf[currency] -= amount;
            currency.transfer(to, amount);
        }
    }

    function settle(Currency currency) external payable onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // subtraction must be safe
        _accountDelta(currency, -(paid.toInt256()));
    }

    function whitelist(address provider) external onlyOwner {
        isWhitelisted[provider] = true;
        emit Whitelist(provider);
    }

    function delist(address provider) external onlyOwner {
        isWhitelisted[provider] = false;
        emit Delist(provider);
    }

    function setDefaultProvider(address newDefaultProvider) public onlyOwner {
        address oldDefaultProvider = defaultProvider;
        defaultProvider = newDefaultProvider;
        emit SetDefaultProvider(oldDefaultProvider, newDefaultProvider);
    }

    function _getAndIncrementNonce(uint256 id) internal override returns (uint256 nonce) {
        OrderId orderId = OrderId.wrap(id);
        nonce = _orders[orderId].nonce;
        _orders[orderId].nonce = uint32(nonce) + 1;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _accountDelta(Currency currency, int256 delta) internal {
        if (delta == 0) return;

        address locker = Lockers.getCurrentLocker();
        int256 current = currencyDelta[locker][currency];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                Lockers.decrementNonzeroDeltaCount();
            } else if (current == 0) {
                Lockers.incrementNonzeroDeltaCount();
            }
        }

        currencyDelta[locker][currency] = next;
    }

    function _calculateFee(uint256 amount, int24 rate) internal pure returns (int256) {
        bool positive = rate > 0;
        uint256 absRate;
        unchecked {
            absRate = uint256(uint24(positive ? rate : -rate));
        }
        // @dev absFee must be less than type(int256).max
        uint256 absFee = Math.divide(amount * absRate, uint256(_RATE_PRECISION), positive);
        return positive ? int256(absFee) : -int256(absFee);
    }

    function _calculateAmountInReverse(uint256 amount, int24 rate) internal pure returns (uint256 adjustedAmount) {
        uint256 fee = Math.divide(amount * uint256(_RATE_PRECISION), uint256(_RATE_PRECISION - rate), rate < 0);
        adjustedAmount = rate > 0 ? amount - fee : amount + fee;
    }

    function _ownerOf(uint256 tokenId) internal view override returns (address) {
        return _orders[OrderId.wrap(tokenId)].owner;
    }

    function _setOwner(uint256 tokenId, address owner) internal override {
        _orders[OrderId.wrap(tokenId)].owner = owner;
    }

    function load(bytes32 slot) external view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }

    function load(bytes32 startSlot, uint256 nSlot) external view returns (bytes memory value) {
        value = new bytes(32 * nSlot);

        assembly {
            for { let i := 0 } lt(i, nSlot) { i := add(i, 1) } {
                mstore(add(value, mul(add(i, 1), 32)), sload(add(startSlot, i)))
            }
        }
    }

    receive() external payable {}
}
