// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "../libraries/Book.sol";
import "../libraries/Currency.sol";
import "../libraries/OrderId.sol";
import "../libraries/Tick.sol";

interface IBookManager {
    error Slippage(BookId bookId);
    error LockedBy(address locker);
    error CurrencyNotSettled();
    error NotWhitelisted(address provider);

    event SetTreasury(address indexed oldTreasury, address indexed newTreasury);
    event Whitelist(address indexed provider);
    event Delist(address indexed provider);

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

    struct MakeParams {
        BookKey key;
        address user;
        Tick tick;
        uint64 amount; // times 10**unitDecimals to get actual bid amount
        /// @notice The limit order service provider address to collect fees
        address provider;
        uint32 bounty;
    }

    function treasury() external view returns (address);

    function getBookKey(BookId id) external view returns (BookKey memory);

    function getOrder(OrderId id) external view returns (Book.Order memory);

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

    function whitelist(address[] calldata providers) external;

    function delist(address[] calldata providers) external;

    function isWhitelisted(address provider) external view returns (bool);

    function tokenOwed(address user, Currency currency) external view returns (uint256);

    function lockData() external view returns (uint128, uint128);

    function currencyDelta(address locker, Currency currency) external view returns (int256);

    function reservesOf(Currency currency) external view returns (uint256);

    function lock(bytes calldata data) external returns (bytes memory);

    function setTreasury(address newTreasury) external;
}
