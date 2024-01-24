// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../libraries/Book.sol";
import "../libraries/Currency.sol";
import "../libraries/OrderId.sol";
import "../libraries/Tick.sol";
import "./IERC721Permit.sol";
import "./IHooks.sol";

interface IBookManager is IERC721Metadata, IERC721Permit {
    error InvalidUnit();
    error InvalidFeePolicy();
    error Slippage(BookId bookId);
    error LockedBy(address locker, address hook);
    error CurrencyNotSettled();
    error NotWhitelisted(address provider);

    event Open(
        BookId indexed id,
        Currency indexed base,
        Currency indexed quote,
        uint96 unit,
        FeePolicy makerPolicy,
        FeePolicy takerPolicy,
        IHooks hooks
    );
    event Take(BookId indexed bookId, address indexed user, Tick tick, uint64 amount);
    event Make(BookId indexed bookId, address indexed user, uint64 amount, uint256 orderIndex, Tick tick);
    event Cancel(OrderId indexed orderId, uint64 canceledAmount);
    event Claim(address indexed claimer, OrderId indexed orderId, uint64 rawAmount);
    event Whitelist(address indexed provider);
    event Delist(address indexed provider);
    event Collect(address indexed provider, Currency indexed currency, uint256 amount);
    event SetDefaultProvider(address indexed oldDefaultProvider, address indexed newDefaultProvider);

    struct Order {
        uint64 initial;
        uint32 nonce;
        address provider;
        uint64 pending; // Unclaimed amount
        address owner;
    }

    struct BookKey {
        Currency base;
        uint96 unit;
        Currency quote;
        FeePolicy makerPolicy;
        FeePolicy takerPolicy;
        IHooks hooks;
    }

    struct FeePolicy {
        int24 rate;
        bool useOutput;
    }

    function baseURI() external view returns (string memory);

    function defaultProvider() external view returns (address);

    function currencyDelta(address locker, Currency currency) external view returns (int256);

    function reservesOf(Currency currency) external view returns (uint256);

    function isWhitelisted(address provider) external view returns (bool);

    function tokenOwed(address provider, Currency currency) external view returns (uint256);

    function getBookKey(BookId id) external view returns (BookKey memory);

    function getOrder(OrderId id) external view returns (Order memory);

    function getLock(uint256 i) external view returns (address locker, address lockCaller);

    function getLockData() external view returns (uint128, uint128);

    function open(BookKey calldata key, bytes calldata hookData) external;

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
        uint64 amount;
    }

    function take(TakeParams calldata params, bytes calldata hookData)
        external
        returns (uint256 quoteAmount, uint256 baseAmount);

    struct CancelParams {
        OrderId id;
        uint64 to;
    }

    function cancel(CancelParams calldata params, bytes calldata hookData) external;

    function claim(OrderId id, bytes calldata hookData) external;

    function collect(address provider, Currency currency) external;

    function withdraw(Currency currency, address to, uint256 amount) external;

    function settle(Currency currency) external payable returns (uint256);

    function whitelist(address[] calldata providers) external;

    function delist(address[] calldata providers) external;

    function setDefaultProvider(address newDefaultProvider) external;
}
