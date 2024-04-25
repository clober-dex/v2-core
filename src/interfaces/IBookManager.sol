// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import {BookId} from "../libraries/BookId.sol";
import {Currency} from "../libraries/Currency.sol";
import {OrderId} from "../libraries/OrderId.sol";
import {Tick} from "../libraries/Tick.sol";
import {FeePolicy} from "../libraries/FeePolicy.sol";
import {IERC721Permit} from "./IERC721Permit.sol";
import {IHooks} from "./IHooks.sol";

/**
 * @title IBookManager
 * @notice The interface for the BookManager contract
 */
interface IBookManager is IERC721Metadata, IERC721Permit {
    error InvalidUnitSize();
    error InvalidFeePolicy();
    error InvalidProvider(address provider);
    error LockedBy(address locker, address hook);
    error CurrencyNotSettled();

    /**
     * @notice Event emitted when a new book is opened
     * @param id The book id
     * @param base The base currency
     * @param quote The quote currency
     * @param unitSize The unit size of the book
     * @param makerPolicy The maker fee policy
     * @param takerPolicy The taker fee policy
     * @param hooks The hooks contract
     */
    event Open(
        BookId indexed id,
        Currency indexed base,
        Currency indexed quote,
        uint64 unitSize,
        FeePolicy makerPolicy,
        FeePolicy takerPolicy,
        IHooks hooks
    );

    /**
     * @notice Event emitted when a new order is made
     * @param bookId The book id
     * @param user The user address
     * @param tick The order tick
     * @param orderIndex The order index
     * @param unit The order unit
     * @param provider The provider address
     */
    event Make(
        BookId indexed bookId, address indexed user, Tick tick, uint256 orderIndex, uint64 unit, address provider
    );

    /**
     * @notice Event emitted when an order is taken
     * @param bookId The book id
     * @param user The user address
     * @param tick The order tick
     * @param unit The order unit
     */
    event Take(BookId indexed bookId, address indexed user, Tick tick, uint64 unit);

    /**
     * @notice Event emitted when an order is canceled
     * @param orderId The order id
     * @param unit The canceled unit
     */
    event Cancel(OrderId indexed orderId, uint64 unit);

    /**
     * @notice Event emitted when an order is claimed
     * @param orderId The order id
     * @param unit The claimed unit
     */
    event Claim(OrderId indexed orderId, uint64 unit);

    /**
     * @notice Event emitted when a provider is whitelisted
     * @param provider The provider address
     */
    event Whitelist(address indexed provider);

    /**
     * @notice Event emitted when a provider is delisted
     * @param provider The provider address
     */
    event Delist(address indexed provider);

    /**
     * @notice Event emitted when a provider collects fees
     * @param provider The provider address
     * @param recipient The recipient address
     * @param currency The currency
     * @param amount The collected amount
     */
    event Collect(address indexed provider, address indexed recipient, Currency indexed currency, uint256 amount);

    /**
     * @notice Event emitted when new default provider is set
     * @param newDefaultProvider The new default provider address
     */
    event SetDefaultProvider(address indexed newDefaultProvider);

    /**
     * @notice This structure represents a unique identifier for a book in the BookManager.
     * @param base The base currency of the book
     * @param unitSize The unit size of the book
     * @param quote The quote currency of the book
     * @param makerPolicy The maker fee policy of the book
     * @param hooks The hooks contract of the book
     * @param takerPolicy The taker fee policy of the book
     */
    struct BookKey {
        Currency base;
        uint64 unitSize;
        Currency quote;
        FeePolicy makerPolicy;
        IHooks hooks;
        FeePolicy takerPolicy;
    }

    /**
     * @notice Returns the base URI
     * @return The base URI
     */
    function baseURI() external view returns (string memory);

    /**
     * @notice Returns the contract URI
     * @return The contract URI
     */
    function contractURI() external view returns (string memory);

    /**
     * @notice Returns the default provider
     * @return The default provider
     */
    function defaultProvider() external view returns (address);

    /**
     * @notice Returns the total reserves of a given currency
     * @param currency The currency in question
     * @return The total reserves amount
     */
    function reservesOf(Currency currency) external view returns (uint256);

    /**
     * @notice Checks if a provider is whitelisted
     * @param provider The address of the provider
     * @return True if the provider is whitelisted, false otherwise
     */
    function isWhitelisted(address provider) external view returns (bool);

    /**
     * @notice Verifies if an owner has authorized a spender for a token
     * @param owner The address of the token owner
     * @param spender The address of the spender
     * @param tokenId The token ID
     */
    function checkAuthorized(address owner, address spender, uint256 tokenId) external view;

    /**
     * @notice Calculates the amount owed to a provider in a given currency
     * @param provider The provider's address
     * @param currency The currency in question
     * @return The owed amount
     */
    function tokenOwed(address provider, Currency currency) external view returns (uint256);

    /**
     * @notice Calculates the currency balance changes for a given locker
     * @param locker The address of the locker
     * @param currency The currency in question
     * @return The net change in currency balance
     */
    function getCurrencyDelta(address locker, Currency currency) external view returns (int256);

    /**
     * @notice Retrieves the book key for a given book ID
     * @param id The book ID
     * @return The book key
     */
    function getBookKey(BookId id) external view returns (BookKey memory);

    /**
     * @notice This structure represents a current status for an order in the BookManager.
     * @param provider The provider of the order
     * @param open The open unit of the order
     * @param claimable The claimable unit of the order
     */
    struct OrderInfo {
        address provider;
        uint64 open;
        uint64 claimable;
    }

    /**
     * @notice Provides information about an order
     * @param id The order ID
     * @return Order information including provider, open status, and claimable unit
     */
    function getOrder(OrderId id) external view returns (OrderInfo memory);

    /**
     * @notice Retrieves the locker and caller addresses for a given lock
     * @param i The index of the lock
     * @return locker The locker's address
     * @return lockCaller The caller's address
     */
    function getLock(uint256 i) external view returns (address locker, address lockCaller);

    /**
     * @notice Provides the lock data
     * @return The lock data including necessary numeric values
     */
    function getLockData() external view returns (uint128, uint128);

    /**
     * @notice Returns the depth of a given book ID and tick
     * @param id The book ID
     * @param tick The tick
     * @return The depth of the tick
     */
    function getDepth(BookId id, Tick tick) external view returns (uint64);

    /**
     * @notice Retrieves the highest tick for a given book ID
     * @param id The book ID
     * @return tick The highest tick
     */
    function getHighest(BookId id) external view returns (Tick tick);

    /**
     * @notice Finds the maximum tick less than a specified tick in a book
     * @dev Returns `Tick.wrap(type(int24).min)` if the specified tick is the lowest
     * @param id The book ID
     * @param tick The specified tick
     * @return The next lower tick
     */
    function maxLessThan(BookId id, Tick tick) external view returns (Tick);

    /**
     * @notice Checks if a book is opened
     * @param id The book ID
     * @return True if the book is opened, false otherwise
     */
    function isOpened(BookId id) external view returns (bool);

    /**
     * @notice Checks if a book is empty
     * @param id The book ID
     * @return True if the book is empty, false otherwise
     */
    function isEmpty(BookId id) external view returns (bool);

    /**
     * @notice Encodes a BookKey into a BookId
     * @param key The BookKey to encode
     * @return The encoded BookId
     */
    function encodeBookKey(BookKey calldata key) external pure returns (BookId);

    /**
     * @notice Loads a value from a specific storage slot
     * @param slot The storage slot
     * @return The value in the slot
     */
    function load(bytes32 slot) external view returns (bytes32);

    /**
     * @notice Loads a sequence of values starting from a specific slot
     * @param startSlot The starting slot
     * @param nSlot The number of slots to load
     * @return The sequence of values
     */
    function load(bytes32 startSlot, uint256 nSlot) external view returns (bytes memory);

    /**
     * @notice Opens a new book
     * @param key The book key
     * @param hookData The hook data
     */
    function open(BookKey calldata key, bytes calldata hookData) external;

    /**
     * @notice Locks a book manager function
     * @param locker The locker address
     * @param data The lock data
     * @return The lock return data
     */
    function lock(address locker, bytes calldata data) external returns (bytes memory);

    /**
     * @notice This structure represents the parameters for making an order.
     * @param key The book key for the order
     * @param tick The tick for the order
     * @param unit The unit for the order. Times key.unitSize to get actual bid amount.
     * @param provider The provider for the order. The limit order service provider address to collect fees.
     */
    struct MakeParams {
        BookKey key;
        Tick tick;
        uint64 unit;
        address provider;
    }

    /**
     * @notice Make a limit order
     * @param params The order parameters
     * @param hookData The hook data
     * @return id The order id. Returns 0 if the order is not settled
     * @return quoteAmount The amount of quote currency to be paid
     */
    function make(MakeParams calldata params, bytes calldata hookData)
        external
        returns (OrderId id, uint256 quoteAmount);

    /**
     * @notice This structure represents the parameters for taking orders in the specified tick.
     * @param key The book key for the order
     * @param tick The tick for the order
     * @param maxUnit The max unit to take
     */
    struct TakeParams {
        BookKey key;
        Tick tick;
        uint64 maxUnit;
    }

    /**
     * @notice Take a limit order at specific tick
     * @param params The order parameters
     * @param hookData The hook data
     * @return quoteAmount The amount of quote currency to be received
     * @return baseAmount The amount of base currency to be paid
     */
    function take(TakeParams calldata params, bytes calldata hookData)
        external
        returns (uint256 quoteAmount, uint256 baseAmount);

    /**
     * @notice This structure represents the parameters for canceling an order.
     * @param id The order id for the order
     * @param toUnit The remaining open unit for the order after cancellation. Must not exceed the current open unit.
     */
    struct CancelParams {
        OrderId id;
        uint64 toUnit;
    }

    /**
     * @notice Cancel a limit order
     * @param params The order parameters
     * @param hookData The hook data
     * @return canceledAmount The amount of quote currency canceled
     */
    function cancel(CancelParams calldata params, bytes calldata hookData) external returns (uint256 canceledAmount);

    /**
     * @notice Claims an order
     * @param id The order ID
     * @param hookData The hook data
     * @return claimedAmount The amount claimed
     */
    function claim(OrderId id, bytes calldata hookData) external returns (uint256 claimedAmount);

    /**
     * @notice Collects fees from a provider
     * @param recipient The recipient address
     * @param currency The currency
     * @return The collected amount
     */
    function collect(address recipient, Currency currency) external returns (uint256);

    /**
     * @notice Withdraws a currency
     * @param currency The currency
     * @param to The recipient address
     * @param amount The amount
     */
    function withdraw(Currency currency, address to, uint256 amount) external;

    /**
     * @notice Settles a currency
     * @param currency The currency
     * @return The settled amount
     */
    function settle(Currency currency) external payable returns (uint256);

    /**
     * @notice Whitelists a provider
     * @param provider The provider address
     */
    function whitelist(address provider) external;

    /**
     * @notice Delists a provider
     * @param provider The provider address
     */
    function delist(address provider) external;

    /**
     * @notice Sets the default provider
     * @param newDefaultProvider The new default provider address
     */
    function setDefaultProvider(address newDefaultProvider) external;
}
