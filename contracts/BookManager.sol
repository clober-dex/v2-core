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
    int24 private constant _MAX_FEE_RATE = 10 ** 6 / 2;
    int24 private constant _MIN_FEE_RATE = -(10 ** 6 / 2);

    string public override baseURI;
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

    function open(BookKey calldata key, bytes calldata hookData) external {
        // @dev Also, the book opener should set unit at least circulatingTotalSupply / type(uint64).max to avoid overflow.
        //      But it is not checked here because it is not possible to check it without knowing circulatingTotalSupply.
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
        if (params.provider != address(0) && !isWhitelisted[params.provider]) revert InvalidProvider(params.provider);
        params.tick.validate();
        BookId bookId = params.key.toId();
        Book.State storage book = _books[bookId];
        book.checkOpened();

        if (!params.key.hooks.beforeMake(params, hookData)) return (OrderId.wrap(0), 0);

        uint40 orderIndex = book.make(params.tick, params.amount, params.provider);
        id = OrderIdLibrary.encode(bookId, params.tick, orderIndex);
        unchecked {
            // @dev uint64 * uint96 < type(uint256).max
            quoteAmount = uint256(params.amount) * params.key.unit;
        }
        int256 quoteDelta = quoteAmount.toInt256();

        if (!params.key.makerPolicy.useOutput) quoteDelta -= _calculateFee(quoteAmount, params.key.makerPolicy.rate);

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
        address owner = _ownerOf(OrderId.unwrap(params.id));
        _checkAuthorized(owner, msg.sender, OrderId.unwrap(params.id));

        (BookId bookId,,) = params.id.decode();
        Book.State storage book = _books[bookId];
        book.checkOpened();
        BookKey memory key = book.key;

        if (!key.hooks.beforeCancel(params, hookData)) return;

        (uint64 canceled, uint64 pending) = book.cancel(params.id, params.to);

        uint256 canceledAmount;
        unchecked {
            canceledAmount = uint256(canceled) * key.unit;
        }
        FeePolicy memory makerPolicy = key.makerPolicy;

        if (!makerPolicy.useOutput) canceledAmount = _calculateAmountInReverse(canceledAmount, makerPolicy.rate);

        reservesOf[key.quote] -= canceledAmount;
        key.quote.transfer(owner, canceledAmount);

        if (pending == 0) _burn(OrderId.unwrap(params.id));

        key.hooks.afterCancel(params, canceled, hookData);

        emit Cancel(params.id, canceled);
    }

    function claim(OrderId id, bytes calldata hookData) external {
        _requireOwned(OrderId.unwrap(id));

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

        if (!key.hooks.beforeClaim(id, hookData)) return;

        uint64 claimed = book.claim(tick, orderIndex);

        uint256 claimableAmount;
        int256 quoteFee;
        int256 baseFee;
        {
            claimableAmount = tick.rawToBase(claimed, false);
            uint256 claimedInQuote;
            unchecked {
                claimedInQuote = uint256(claimed) * key.unit;
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

        Book.Order memory order = book.getOrder(tick, orderIndex);
        address provider = order.provider;
        if (provider == address(0)) provider = defaultProvider;
        tokenOwed[provider][key.quote] += quoteFee.toUint256();
        tokenOwed[provider][key.base] += baseFee.toUint256();

        // @dev Must load owner before burning
        address owner = _ownerOf(OrderId.unwrap(id));
        if (order.pending == 0) _burn(OrderId.unwrap(id));

        reservesOf[key.base] -= claimableAmount;
        key.base.transfer(owner, claimableAmount);

        key.hooks.afterClaim(id, claimed, hookData);

        emit Claim(msg.sender, id, claimed);
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
