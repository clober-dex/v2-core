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
    using FeePolicyLibrary for FeePolicy;
    using Hooks for IHooks;

    string public override baseURI; // slot 10
    string public override contractURI;
    address public override defaultProvider;

    mapping(address locker => mapping(Currency currency => int256 currencyDelta)) public override currencyDelta;
    mapping(Currency currency => uint256) public override reservesOf;
    mapping(BookId id => Book.State) internal _books;
    mapping(address provider => bool) public override isWhitelisted;
    mapping(address provider => mapping(Currency currency => uint256 amount)) public override tokenOwed;

    constructor(
        address owner_,
        address defaultProvider_,
        string memory baseURI_,
        string memory contractURI_,
        string memory name_,
        string memory symbol_
    ) Ownable(owner_) ERC721Permit(name_, symbol_, "2") {
        setDefaultProvider(defaultProvider_);
        baseURI = baseURI_;
        contractURI = contractURI_;
        Lockers.initialize();
    }

    modifier onlyByLocker() {
        _checkLocker(msg.sender);
        _;
    }

    function checkAuthorized(address owner, address spender, uint256 tokenId) external view {
        _checkAuthorized(owner, spender, tokenId);
    }

    function _checkLocker(address caller) internal view {
        address locker = Lockers.getCurrentLocker();
        IHooks hook = Lockers.getCurrentHook();
        if (caller == locker) return;
        if (caller == address(hook) && hook.hasPermission(Hooks.ACCESS_LOCK_FLAG)) return;
        revert LockedBy(locker, address(hook));
    }

    function getBookKey(BookId id) external view returns (BookKey memory) {
        return _books[id].key;
    }

    function getOrder(OrderId id) external view returns (OrderInfo memory) {
        (BookId bookId, Tick tick, uint40 orderIndex) = id.decode();
        Book.State storage book = _books[bookId];
        Book.Order memory order = book.getOrder(tick, orderIndex);
        uint64 claimable = book.calculateClaimableRawAmount(tick, orderIndex);
        unchecked {
            return OrderInfo({provider: order.provider, open: order.pending - claimable, claimable: claimable});
        }
    }

    function open(BookKey calldata key, bytes calldata hookData) external onlyByLocker {
        // @dev Also, the book opener should set unit at least circulatingTotalSupply / type(uint64).max to avoid overflow.
        //      But it is not checked here because it is not possible to check it without knowing circulatingTotalSupply.
        if (key.unit == 0) revert InvalidUnit();

        if (!(key.makerPolicy.isValid() && key.takerPolicy.isValid())) revert InvalidFeePolicy();
        unchecked {
            if (key.makerPolicy.rate() + key.takerPolicy.rate() < 0) revert InvalidFeePolicy();
        }
        if (key.makerPolicy.rate() < 0 || key.takerPolicy.rate() < 0) {
            if (key.makerPolicy.usesQuote() != key.takerPolicy.usesQuote()) revert InvalidFeePolicy();
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

    function getLowest(BookId id) external view returns (Tick) {
        return _books[id].lowest();
    }

    function isEmpty(BookId id) external view returns (bool) {
        return _books[id].isEmpty();
    }

    function make(MakeParams calldata params, bytes calldata hookData)
        external
        onlyByLocker
        returns (OrderId id, uint256 quoteAmount)
    {
        if (params.provider != address(0) && !isWhitelisted[params.provider]) revert InvalidProvider(params.provider);
        params.tick.validateTick();
        BookId bookId = params.key.toId();
        Book.State storage book = _books[bookId];
        book.checkOpened();

        if (!params.key.hooks.beforeMake(params, hookData)) return (OrderId.wrap(0), 0);

        uint40 orderIndex = book.make(params.tick, params.amount, params.provider);
        id = OrderIdLibrary.encode(bookId, params.tick, orderIndex);
        int256 quoteDelta;
        unchecked {
            // @dev uint64 * uint64 < type(uint256).max
            quoteAmount = uint256(params.amount) * params.key.unit;

            // @dev 0 < uint64 * uint64 + rate * uint64 * uint64 < type(int256).max
            quoteDelta = int256(quoteAmount);
            if (params.key.makerPolicy.usesQuote()) {
                quoteDelta += params.key.makerPolicy.calculateFee(quoteAmount, false);
                quoteAmount = uint256(quoteDelta);
            }
        }

        _accountDelta(params.key.quote, quoteDelta);

        _mint(msg.sender, OrderId.unwrap(id));

        params.key.hooks.afterMake(params, id, hookData);

        emit Make(bookId, msg.sender, params.tick, orderIndex, params.amount);
    }

    function take(TakeParams calldata params, bytes calldata hookData)
        external
        onlyByLocker
        returns (uint256 quoteAmount, uint256 baseAmount)
    {
        params.tick.validateTick();
        BookId bookId = params.key.toId();
        Book.State storage book = _books[bookId];
        book.checkOpened();

        if (!params.key.hooks.beforeTake(params, hookData)) return (0, 0);

        uint64 takenAmount = book.take(params.tick, params.maxAmount);
        unchecked {
            quoteAmount = uint256(takenAmount) * params.key.unit;
        }
        baseAmount = params.tick.quoteToBase(quoteAmount, true);

        int256 quoteDelta = int256(quoteAmount);
        int256 baseDelta = baseAmount.toInt256();
        if (params.key.takerPolicy.usesQuote()) {
            quoteDelta -= params.key.takerPolicy.calculateFee(quoteAmount, false);
            quoteAmount = uint256(quoteDelta);
        } else {
            baseDelta += params.key.takerPolicy.calculateFee(baseAmount, false);
            baseAmount = uint256(baseDelta);
        }
        _accountDelta(params.key.quote, -quoteDelta);
        _accountDelta(params.key.base, baseDelta);

        params.key.hooks.afterTake(params, takenAmount, hookData);

        emit Take(bookId, msg.sender, params.tick, takenAmount);
    }

    function cancel(CancelParams calldata params, bytes calldata hookData)
        external
        onlyByLocker
        returns (uint256 canceledAmount)
    {
        _checkAuthorized(_ownerOf(OrderId.unwrap(params.id)), msg.sender, OrderId.unwrap(params.id));

        (BookId bookId,,) = params.id.decode();
        Book.State storage book = _books[bookId];
        BookKey memory key = book.key;

        if (!key.hooks.beforeCancel(params, hookData)) return 0;

        (uint64 canceled, uint64 pending) = book.cancel(params.id, params.to);

        unchecked {
            canceledAmount = uint256(canceled) * key.unit;
            int256 quoteFee = key.makerPolicy.calculateFee(canceledAmount, true);
            canceledAmount = uint256(int256(canceledAmount) + quoteFee);
        }

        if (pending == 0) _burn(OrderId.unwrap(params.id));

        _accountDelta(key.quote, -int256(canceledAmount));

        key.hooks.afterCancel(params, canceled, hookData);

        emit Cancel(params.id, canceled);
    }

    function claim(OrderId id, bytes calldata hookData) external onlyByLocker returns (uint256 claimedAmount) {
        _checkAuthorized(_ownerOf(OrderId.unwrap(id)), msg.sender, OrderId.unwrap(id));

        Tick tick;
        uint40 orderIndex;
        Book.State storage book;
        {
            BookId bookId;
            (bookId, tick, orderIndex) = id.decode();
            book = _books[bookId];
        }
        IBookManager.BookKey memory key = book.key;

        if (!key.hooks.beforeClaim(id, hookData)) return 0;

        uint64 claimedRaw = book.claim(tick, orderIndex);

        int256 quoteFee;
        int256 baseFee;
        {
            uint256 claimedInQuote;
            unchecked {
                claimedInQuote = uint256(claimedRaw) * key.unit;
            }
            claimedAmount = tick.quoteToBase(claimedInQuote, false);

            FeePolicy makerPolicy = key.makerPolicy;
            FeePolicy takerPolicy = key.takerPolicy;
            if (takerPolicy.usesQuote()) {
                quoteFee = takerPolicy.calculateFee(claimedInQuote, true);
            } else {
                baseFee = takerPolicy.calculateFee(claimedAmount, true);
            }

            if (makerPolicy.usesQuote()) {
                quoteFee += makerPolicy.calculateFee(claimedInQuote, true);
            } else {
                int256 makeFee = makerPolicy.calculateFee(claimedAmount, false);
                baseFee += makeFee;
                claimedAmount = makeFee > 0 ? claimedAmount - uint256(makeFee) : claimedAmount + uint256(-makeFee);
            }
        }

        Book.Order memory order = book.getOrder(tick, orderIndex);
        address provider = order.provider;
        if (provider == address(0)) provider = defaultProvider;
        if (quoteFee > 0) tokenOwed[provider][key.quote] += quoteFee.toUint256();
        if (baseFee > 0) tokenOwed[provider][key.base] += baseFee.toUint256();

        if (order.pending == 0) _burn(OrderId.unwrap(id));

        _accountDelta(key.base, -claimedAmount.toInt256());

        key.hooks.afterClaim(id, claimedRaw, hookData);

        emit Claim(id, claimedRaw);
    }

    function collect(address provider, Currency currency) external {
        uint256 amount = tokenOwed[provider][currency];
        if (amount > 0) {
            tokenOwed[provider][currency] = 0;
            reservesOf[currency] -= amount;
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

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _accountDelta(Currency currency, int256 delta) internal {
        if (delta == 0) return;

        address locker = Lockers.getCurrentLocker();
        int256 current = currencyDelta[locker][currency];
        int256 next = current + delta;

        unchecked {
            if (next == 0) Lockers.decrementNonzeroDeltaCount();
            else if (current == 0) Lockers.incrementNonzeroDeltaCount();
        }

        currencyDelta[locker][currency] = next;
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
