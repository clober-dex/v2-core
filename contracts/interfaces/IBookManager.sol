// SPDX-License-Identifier: GPL-2.0-or-later

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
    error InvalidProvider(address provider);
    error LockedBy(address locker, address hook);
    error CurrencyNotSettled();

    event Open(
        BookId indexed id,
        Currency indexed base,
        Currency indexed quote,
        uint64 unit,
        FeePolicy makerPolicy,
        FeePolicy takerPolicy,
        IHooks hooks
    );
    event Make(BookId indexed bookId, address indexed user, Tick tick, uint256 orderIndex, uint64 amount);
    event Take(BookId indexed bookId, address indexed user, Tick tick, uint64 amount);
    event Cancel(OrderId indexed orderId, uint64 canceledAmount);
    event Claim(address indexed claimer, OrderId indexed orderId, uint64 rawAmount);
    event Whitelist(address indexed provider);
    event Delist(address indexed provider);
    event Collect(address indexed provider, Currency indexed currency, uint256 amount);
    event SetDefaultProvider(address indexed oldDefaultProvider, address indexed newDefaultProvider);

    struct BookKey {
        Currency base;
        uint64 unit;
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

    function contractURI() external view returns (string memory);

    function defaultProvider() external view returns (address);

    function currencyDelta(address locker, Currency currency) external view returns (int256);

    function reservesOf(Currency currency) external view returns (uint256);

    function isWhitelisted(address provider) external view returns (bool);

    function tokenOwed(address provider, Currency currency) external view returns (uint256);

    function getBookKey(BookId id) external view returns (BookKey memory);

    struct OrderInfo {
        address provider;
        uint64 open;
        uint64 claimable;
    }

    function getOrder(OrderId id) external view returns (OrderInfo memory);

    function getLock(uint256 i) external view returns (address locker, address lockCaller);

    function getLockData() external view returns (uint128, uint128);

    function getDepth(BookId id, Tick tick) external view returns (uint64);

    function getRoot(BookId id) external view returns (Tick tick);

    function isEmpty(BookId id) external view returns (bool);

    function load(bytes32 slot) external view returns (bytes32);

    function load(bytes32 startSlot, uint256 nSlot) external view returns (bytes memory);

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
        uint64 maxAmount;
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

    function whitelist(address provider) external;

    function delist(address provider) external;

    function setDefaultProvider(address newDefaultProvider) external;
}
