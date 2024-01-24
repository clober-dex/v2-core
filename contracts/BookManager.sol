// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "./libraries/BookId.sol";
import "./libraries/Book.sol";
import "./libraries/OrderId.sol";
import "./libraries/Lockers.sol";
import "./interfaces/IPositionLocker.sol";
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

    uint256 private constant _CLAIM_BOUNTY_UNIT = 1 gwei;
    int256 private constant _RATE_PRECISION = 10 ** 6;
    int256 private constant _MAX_FEE_RATE = 10 ** 6 / 2;
    int256 private constant _MIN_FEE_RATE = -10 ** 6 / 2;

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
        _books[id].initialize(key);

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

    function make(MakeParams calldata params, bytes calldata hookData) external onlyByLocker returns (OrderId id) {
        if (params.provider != address(0) && !isWhitelisted[params.provider]) {
            revert NotWhitelisted(params.provider);
        }
        params.tick.validate();
        BookId bookId = params.key.toId();
        Book.State storage book = _books[bookId];
        book.checkInitialized();

        if (!params.key.hooks.beforeMake(params.key, params, hookData)) return OrderId.wrap(0);

        uint40 orderIndex = book.make(_orders, bookId, params.tick, params.amount);
        id = OrderIdLibrary.encode(bookId, params.tick, orderIndex);
        uint256 quoteAmount = uint256(params.amount) * params.key.unit;
        if (!params.key.makerPolicy.useOutput) {
            (quoteAmount,) = _calculateFee(quoteAmount, params.key.makerPolicy.rate);
        }
        _accountDelta(params.key.quote, quoteAmount.toInt256());
        _accountDelta(CurrencyLibrary.NATIVE, (_CLAIM_BOUNTY_UNIT * params.bounty).toInt256());

        _orders[id] = IBookManager.Order({
            initial: params.amount,
            nonce: 0,
            owner: msg.sender,
            pending: params.amount,
            bounty: params.bounty,
            provider: params.provider
        });
        _mint(msg.sender, OrderId.unwrap(id));

        params.key.hooks.afterMake(params.key, params, id, hookData);

        emit Make(bookId, msg.sender, params.amount, params.bounty, orderIndex, params.tick);
    }

    function take(TakeParams calldata params, bytes calldata hookData) external onlyByLocker {
        BookId bookId = params.key.toId();
        Book.State storage book = _books[bookId];
        book.checkInitialized();

        if (!params.key.hooks.beforeTake(params.key, params, hookData)) return;

        (Tick tick, uint256 baseAmount) = book.take(params.amount);
        uint256 quoteAmount = uint256(params.amount) * params.key.unit;
        if (params.key.takerPolicy.useOutput) {
            (quoteAmount,) = _calculateFee(quoteAmount, params.key.takerPolicy.rate);
        } else {
            (baseAmount,) = _calculateFee(baseAmount, params.key.takerPolicy.rate);
        }

        _accountDelta(params.key.quote, -quoteAmount.toInt256());
        _accountDelta(params.key.base, baseAmount.toInt256());

        params.key.hooks.afterTake(params.key, params, hookData);

        emit Take(bookId, msg.sender, tick, params.amount);
    }

    function cancel(CancelParams calldata params, bytes calldata hookData) external onlyByLocker {
        (BookId bookId, Tick tick, uint40 orderIndex) = params.id.decode();

        Book.State storage book = _books[bookId];
        BookKey memory key = book.key;
        book.checkInitialized();
        _checkAuthorized(_orders[params.id].owner, _msgSender(), OrderId.unwrap(params.id));

        uint64 pending = _orders[params.id].pending;
        uint64 claimableRaw = book.calculateClaimableRawAmount(pending, tick, orderIndex);
        if (pending == claimableRaw) return;

        if (!key.hooks.beforeCancel(key, params, hookData)) return;

        uint64 canceledRaw = book.cancel(tick, orderIndex, pending, claimableRaw, params.to);
        unchecked {
            _orders[params.id].pending = params.to + claimableRaw;
        }

        uint256 canceledAmount = uint256(canceledRaw) * key.unit;
        FeePolicy memory makerPolicy = key.makerPolicy;
        if (!makerPolicy.useOutput) {
            canceledAmount = _calculateAmountInReverse(canceledAmount, makerPolicy.rate);
        }
        _accountDelta(key.quote, -canceledAmount.toInt256());

        if (claimableRaw == 0) _burn(params.id);

        key.hooks.afterCancel(key, params, canceledRaw, hookData);

        emit Cancel(params.id, canceledRaw);
    }

    function claim(OrderId id, bytes calldata hookData) external onlyByLocker {
        Tick tick;
        uint40 orderIndex;
        Book.State storage book;
        {
            BookId bookId;
            (bookId, tick, orderIndex) = id.decode();
            book = _books[bookId];
        }
        book.checkInitialized();
        IBookManager.BookKey memory key = book.key;
        Order storage order = _orders[id];

        uint64 claimableRaw = book.calculateClaimableRawAmount(order.pending, tick, orderIndex);
        if (claimableRaw == 0) return;

        if (!key.hooks.beforeClaim(key, id, hookData)) return;

        unchecked {
            order.pending -= claimableRaw;
        }

        int256 quoteFee;
        int256 baseFee;
        {
            uint256 claimedInBase = tick.rawToBase(claimableRaw, false);
            uint256 claimedInQuote = uint256(claimableRaw) * key.unit;
            FeePolicy memory makerPolicy = key.makerPolicy;
            FeePolicy memory takerPolicy = key.takerPolicy;
            if (takerPolicy.useOutput) {
                (, quoteFee) = _calculateFee(claimedInQuote, takerPolicy.rate);
            } else {
                (, baseFee) = _calculateFee(claimedInBase, takerPolicy.rate);
            }
            if (makerPolicy.useOutput) {
                int256 makerFee;
                (claimedInBase, makerFee) = _calculateFee(claimedInBase, makerPolicy.rate);
                baseFee += makerFee;
                _accountDelta(key.base, -claimedInBase.toInt256());
            } else {
                int256 makerFee;
                (, makerFee) = _calculateFee(claimedInQuote, makerPolicy.rate);
                quoteFee += makerFee;
            }
        }

        address provider = order.provider;
        if (provider == address(0)) {
            provider = defaultProvider;
        }
        tokenOwed[provider][key.quote] += quoteFee.toUint256();
        tokenOwed[provider][key.base] += baseFee.toUint256();

        if (order.pending == 0) _burn(id);

        key.hooks.afterClaim(key, id, claimableRaw, hookData);

        emit Claim(msg.sender, id, claimableRaw, order.bounty);
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
        if (amount == 0) return;
        _accountDelta(currency, amount.toInt256());
        reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    function settle(Currency currency) external payable onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // subtraction must be safe
        _accountDelta(currency, -(paid.toInt256()));
    }

    function whitelist(address[] calldata providers) external onlyOwner {
        for (uint256 i = 0; i < providers.length; ++i) {
            _whitelist(providers[i]);
        }
    }

    function delist(address[] calldata providers) external onlyOwner {
        for (uint256 i = 0; i < providers.length; ++i) {
            _delist(providers[i]);
        }
    }

    function setDefaultProvider(address newDefaultProvider) public onlyOwner {
        address oldDefaultProvider = defaultProvider;
        defaultProvider = newDefaultProvider;
        _delist(oldDefaultProvider);
        _whitelist(newDefaultProvider);
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

    function _burn(OrderId id) internal {
        _accountDelta(CurrencyLibrary.NATIVE, -(_CLAIM_BOUNTY_UNIT * _orders[id].bounty).toInt256());
        _burn(OrderId.unwrap(id));
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
    // TODO: how to get list of all orders?
}
