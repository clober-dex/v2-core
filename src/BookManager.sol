// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE_V2.pdf

pragma solidity ^0.8.20;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IBookManager} from "./interfaces/IBookManager.sol";
import {ILocker} from "./interfaces/ILocker.sol";
import {IHooks} from "./interfaces/IHooks.sol";
import {BookId, BookIdLibrary} from "./libraries/BookId.sol";
import {Book} from "./libraries/Book.sol";
import {Currency, CurrencyLibrary} from "./libraries/Currency.sol";
import {FeePolicy, FeePolicyLibrary} from "./libraries/FeePolicy.sol";
import {Tick, TickLibrary} from "./libraries/Tick.sol";
import {OrderId, OrderIdLibrary} from "./libraries/OrderId.sol";
import {Lockers} from "./libraries/Lockers.sol";
import {CurrencyDelta} from "./libraries/CurrencyDelta.sol";
import {ERC721Permit} from "./libraries/ERC721Permit.sol";
import {Hooks} from "./libraries/Hooks.sol";

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
        _setDefaultProvider(defaultProvider_);
        baseURI = baseURI_;
        contractURI = contractURI_;
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
        if (caller == address(hook)) return;
        revert LockedBy(locker, address(hook));
    }

    function getBookKey(BookId id) external view returns (BookKey memory) {
        return _books[id].key;
    }

    function getOrder(OrderId id) external view returns (OrderInfo memory) {
        (BookId bookId, Tick tick, uint40 orderIndex) = id.decode();
        Book.State storage book = _books[bookId];
        Book.Order memory order = book.getOrder(tick, orderIndex);
        uint64 claimable = book.calculateClaimableUnit(tick, orderIndex);
        unchecked {
            return OrderInfo({provider: order.provider, open: order.pending - claimable, claimable: claimable});
        }
    }

    function open(BookKey calldata key, bytes calldata hookData) external onlyByLocker {
        // @dev Also, the book opener should set unit size at least circulatingTotalSupply / type(uint64).max to avoid overflow.
        //      But it is not checked here because it is not possible to check it without knowing circulatingTotalSupply.
        if (key.unitSize == 0) revert InvalidUnitSize();

        FeePolicy makerPolicy = key.makerPolicy;
        FeePolicy takerPolicy = key.takerPolicy;
        if (!(makerPolicy.isValid() && takerPolicy.isValid())) revert InvalidFeePolicy();
        unchecked {
            if (makerPolicy.rate() + takerPolicy.rate() < 0) revert InvalidFeePolicy();
        }
        if (makerPolicy.rate() < 0 || takerPolicy.rate() < 0) {
            if (makerPolicy.usesQuote() != takerPolicy.usesQuote()) revert InvalidFeePolicy();
        }
        IHooks hooks = key.hooks;
        if (!hooks.isValidHookAddress()) revert Hooks.HookAddressNotValid(address(hooks));

        hooks.beforeOpen(key, hookData);

        BookId id = key.toId();
        _books[id].open(key);

        emit Open(id, key.base, key.quote, key.unitSize, makerPolicy, takerPolicy, hooks);

        hooks.afterOpen(key, hookData);
    }

    function lock(address locker, bytes calldata data) external returns (bytes memory result) {
        // Add the locker to the stack
        Lockers.push(locker, msg.sender);

        // The locker does everything in this callback, including paying what they owe via calls to settle
        result = ILocker(locker).lockAcquired(msg.sender, data);

        // Remove the locker from the stack
        Lockers.pop();

        (uint128 length, uint128 nonzeroDeltaCount) = Lockers.lockData();
        // @dev The locker must settle all currency balances to zero.
        if (length == 0 && nonzeroDeltaCount != 0) revert CurrencyNotSettled();
    }

    function getCurrencyDelta(address locker, Currency currency) external view returns (int256) {
        return CurrencyDelta.get(locker, currency);
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

    function getHighest(BookId id) external view returns (Tick) {
        return _books[id].highest();
    }

    function maxLessThan(BookId id, Tick tick) external view returns (Tick) {
        return _books[id].maxLessThan(tick);
    }

    function isOpened(BookId id) external view returns (bool) {
        return _books[id].isOpened();
    }

    function isEmpty(BookId id) external view returns (bool) {
        return _books[id].isEmpty();
    }

    function encodeBookKey(BookKey calldata key) external pure returns (BookId) {
        return key.toId();
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

        params.key.hooks.beforeMake(params, hookData);

        uint40 orderIndex = book.make(params.tick, params.unit, params.provider);
        id = OrderIdLibrary.encode(bookId, params.tick, orderIndex);
        int256 quoteDelta;
        unchecked {
            // @dev uint64 * uint64 < type(uint256).max
            quoteAmount = uint256(params.unit) * params.key.unitSize;

            // @dev 0 < uint64 * uint64 + rate * uint64 * uint64 < type(int256).max
            quoteDelta = int256(quoteAmount);
            if (params.key.makerPolicy.usesQuote()) {
                quoteDelta += params.key.makerPolicy.calculateFee(quoteAmount, false);
                quoteAmount = uint256(quoteDelta);
            }
        }

        _accountDelta(params.key.quote, -quoteDelta);

        _mint(msg.sender, OrderId.unwrap(id));

        emit Make(bookId, msg.sender, params.tick, orderIndex, params.unit, params.provider);

        params.key.hooks.afterMake(params, id, hookData);
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

        params.key.hooks.beforeTake(params, hookData);

        uint64 takenUnit = book.take(params.tick, params.maxUnit);
        unchecked {
            quoteAmount = uint256(takenUnit) * params.key.unitSize;
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
        _accountDelta(params.key.quote, quoteDelta);
        _accountDelta(params.key.base, -baseDelta);

        emit Take(bookId, msg.sender, params.tick, takenUnit);

        params.key.hooks.afterTake(params, takenUnit, hookData);
    }

    function cancel(CancelParams calldata params, bytes calldata hookData)
        external
        onlyByLocker
        returns (uint256 canceledAmount)
    {
        _checkAuthorized(_ownerOf(OrderId.unwrap(params.id)), msg.sender, OrderId.unwrap(params.id));

        Book.State storage book = _books[params.id.getBookId()];
        BookKey memory key = book.key;

        key.hooks.beforeCancel(params, hookData);

        (uint64 canceledUnit, uint64 pendingUnit) = book.cancel(params.id, params.toUnit);

        unchecked {
            canceledAmount = uint256(canceledUnit) * key.unitSize;
            if (key.makerPolicy.usesQuote()) {
                int256 quoteFee = key.makerPolicy.calculateFee(canceledAmount, true);
                canceledAmount = uint256(int256(canceledAmount) + quoteFee);
            }
        }

        if (pendingUnit == 0) _burn(OrderId.unwrap(params.id));

        _accountDelta(key.quote, int256(canceledAmount));

        emit Cancel(params.id, canceledUnit);

        key.hooks.afterCancel(params, canceledUnit, hookData);
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

        key.hooks.beforeClaim(id, hookData);

        uint64 claimedUnit = book.claim(tick, orderIndex);

        int256 quoteFee;
        int256 baseFee;
        {
            uint256 claimedInQuote;
            unchecked {
                claimedInQuote = uint256(claimedUnit) * key.unitSize;
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

        _accountDelta(key.base, claimedAmount.toInt256());

        emit Claim(id, claimedUnit);

        key.hooks.afterClaim(id, claimedUnit, hookData);
    }

    function collect(address recipient, Currency currency) external returns (uint256 amount) {
        amount = tokenOwed[msg.sender][currency];
        tokenOwed[msg.sender][currency] = 0;
        reservesOf[currency] -= amount;
        currency.transfer(recipient, amount);
        emit Collect(msg.sender, recipient, currency, amount);
    }

    function withdraw(Currency currency, address to, uint256 amount) external onlyByLocker {
        if (amount > 0) {
            _accountDelta(currency, -amount.toInt256());
            reservesOf[currency] -= amount;
            currency.transfer(to, amount);
        }
    }

    function settle(Currency currency) external payable onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // subtraction must be safe
        _accountDelta(currency, paid.toInt256());
    }

    function whitelist(address provider) external onlyOwner {
        isWhitelisted[provider] = true;
        emit Whitelist(provider);
    }

    function delist(address provider) external onlyOwner {
        isWhitelisted[provider] = false;
        emit Delist(provider);
    }

    function setDefaultProvider(address newDefaultProvider) external onlyOwner {
        _setDefaultProvider(newDefaultProvider);
    }

    function _setDefaultProvider(address newDefaultProvider) internal {
        defaultProvider = newDefaultProvider;
        emit SetDefaultProvider(newDefaultProvider);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function _accountDelta(Currency currency, int256 delta) internal {
        if (delta == 0) return;

        address locker = Lockers.getCurrentLocker();
        int256 next = CurrencyDelta.add(locker, currency, delta);

        if (next == 0) Lockers.decrementNonzeroDeltaCount();
        else if (next == delta) Lockers.incrementNonzeroDeltaCount();
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
