// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../libraries/Book.sol";
import "../libraries/Currency.sol";
import "../libraries/OrderId.sol";
import "../libraries/Tick.sol";
import "./IERC721Permit.sol";

interface IBookManager is IERC721Metadata, IERC721Permit {
    error TickSpacingTooLarge();
    error TickSpacingTooSmall();
    error InvalidUnitDecimals();
    error InvalidFeePolicy();
    error Slippage(BookId bookId);
    error LockedBy(address locker);
    error CurrencyNotSettled();
    error NotWhitelisted(address provider);

    event OpenBook(
        BookId indexed id,
        Currency indexed base,
        Currency indexed quote,
        uint8 unitDecimals,
        uint24 tickSpacing,
        FeePolicy makerPolicy,
        FeePolicy takerPolicy
    );
    event Whitelist(address indexed provider);
    event Delist(address indexed provider);
    event Collect(address indexed provider, Currency indexed currency, uint256 amount);
    event SetDefaultProvider(address indexed oldDefaultProvider, address indexed newDefaultProvider);

    struct Order {
        uint64 initial;
        uint32 nonce;
        address owner;
        uint64 pending; // Unclaimed amount
        uint32 bounty;
        address provider;
    }

    struct BookKey {
        Currency base;
        Currency quote;
        uint8 unitDecimals;
        uint24 tickSpacing;
        FeePolicy makerPolicy;
        FeePolicy takerPolicy;
    }

    struct FeePolicy {
        int24 rate;
        bool useOutput;
    }

    function baseURI() external view returns (string memory);

    function defaultProvider() external view returns (address);

    function lockData() external view returns (uint128, uint128);

    function currencyDelta(address locker, Currency currency) external view returns (int256);

    function reservesOf(Currency currency) external view returns (uint256);

    function isWhitelisted(address provider) external view returns (bool);

    function tokenOwed(address provider, Currency currency) external view returns (uint256);

    function getBookKey(BookId id) external view returns (BookKey memory);

    function getOrder(OrderId id) external view returns (Order memory);

    function openBook(BookKey calldata key) external;

    function lock(bytes calldata data) external returns (bytes memory);

    struct MakeParams {
        BookKey key;
        address user;
        Tick tick;
        uint64 amount; // times 10**unitDecimals to get actual bid amount
        /// @notice The limit order service provider address to collect fees
        address provider;
        uint32 bounty;
    }

    function make(MakeParams[] calldata paramsList) external returns (OrderId[] memory ids);

    struct TakeParams {
        BookKey key;
        uint64 amount; // times 10**unitDecimals to get actual output
        Tick limit;
        uint256 maxIn;
    }

    function take(TakeParams[] calldata paramsList) external;

    struct SpendParams {
        BookKey key;
        uint256 amount;
        Tick limit;
        uint256 minOut;
    }

    function spend(SpendParams[] calldata paramsList) external;

    struct ReduceParams {
        OrderId id;
        uint64 to;
    }

    function reduce(ReduceParams[] calldata paramsList) external;

    function cancel(OrderId[] calldata ids) external;

    function claim(OrderId[] calldata ids) external;

    function collect(address provider, Currency currency) external;

    function withdraw(Currency currency, address to, uint256 amount) external;

    function settle(Currency currency) external payable returns (uint256);

    function whitelist(address[] calldata providers) external;

    function delist(address[] calldata providers) external;

    function setDefaultProvider(address newDefaultProvider) external;
}
