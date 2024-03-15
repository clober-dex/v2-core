// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../libraries/BookId.sol";
import "../libraries/Currency.sol";
import "../libraries/OrderId.sol";
import "../libraries/Tick.sol";
import "../libraries/FeePolicy.sol";
import "./IERC721Permit.sol";
import "./IHooks.sol";

/**
 * @title IBookManager
 * @notice The interface for the BookManager contract
 */
interface IBookManager is IERC721Metadata, IERC721Permit {
    error InvalidUnit();
    error InvalidFeePolicy();
    error InvalidProvider(address provider);
    error LockedBy(address locker, address hook);
    error CurrencyNotSettled();

    /**
     * @notice Event emitted when a new book is opened
     * @param id The book id
     * @param base The base currency
     * @param quote The quote currency
     * @param unit The unit of the book
     * @param makerPolicy The maker fee policy
     * @param takerPolicy The taker fee policy
     * @param hooks The hooks contract
     */
    event Open(
        BookId indexed id,
        Currency indexed base,
        Currency indexed quote,
        uint64 unit,
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
     * @param amount The order amount
     */
    event Make(BookId indexed bookId, address indexed user, Tick tick, uint256 orderIndex, uint64 amount);

    /**
     * @notice Event emitted when an order is taken
     * @param bookId The book id
     * @param user The user address
     * @param tick The order tick
     * @param amount The order amount
     */
    event Take(BookId indexed bookId, address indexed user, Tick tick, uint64 amount);

    /**
     * @notice Event emitted when an order is canceled
     * @param orderId The order id
     * @param canceledAmount The canceled amount
     */
    event Cancel(OrderId indexed orderId, uint64 canceledAmount);

    /**
     * @notice Event emitted when an order is claimed
     * @param orderId The order id
     * @param rawAmount The claimed amount
     */
    event Claim(OrderId indexed orderId, uint64 rawAmount);

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
     * @param currency The currency
     * @param amount The collected amount
     */
    event Collect(address indexed provider, Currency indexed currency, uint256 amount);

    /**
     * @notice Event emitted when new default provider is set
     * @param oldDefaultProvider The old default provider address
     * @param newDefaultProvider The new default provider address
     */
    event SetDefaultProvider(address indexed oldDefaultProvider, address indexed newDefaultProvider);

    struct BookKey {
        Currency base;
        uint64 unit;
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
     * @notice Calculates the currency balance changes for a given locker
     * @param locker The address of the locker
     * @param currency The currency in question
     * @return The net change in currency balance
     */
    function currencyDelta(address locker, Currency currency) external view returns (int256);

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
     * @notice Retrieves the book key for a given book ID
     * @param id The book ID
     * @return The book key
     */
    function getBookKey(BookId id) external view returns (BookKey memory);

    struct OrderInfo {
        address provider;
        uint64 open;
        uint64 claimable;
    }

    /**
     * @notice Provides information about an order
     * @param id The order ID
     * @return Order information including provider, open status, and claimable amount
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
     * @notice Retrieves the lowest tick for a given book ID
     * @param id The book ID
     * @return tick The lowest tick
     */
    function getLowest(BookId id) external view returns (Tick tick);

    /**
     * @notice Finds the minimum tick greater than a specified tick in a book
     * @dev Returns `Tick.wrap(type(int24).min)` if the specified tick is the highest
     * @param id The book ID
     * @param tick The specified tick
     * @return The next higher tick
     */
    function minGreaterThan(BookId id, Tick tick) external view returns (Tick);

    /**
     * @notice Checks if a book is empty
     * @param id The book ID
     * @return True if the book is empty, false otherwise
     */
    function isEmpty(BookId id) external view returns (bool);

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

    struct MakeParams {
        BookKey key;
        Tick tick;
        uint64 amount; // times 10**unitDecimals to get actual bid amount
        /// @notice The limit order service provider address to collect fees
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

    struct TakeParams {
        BookKey key;
        Tick tick;
        uint64 maxAmount;
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

    struct CancelParams {
        OrderId id;
        uint64 to;
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
     * @param provider The provider address
     * @param currency The currency
     */
    function collect(address provider, Currency currency) external;

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
