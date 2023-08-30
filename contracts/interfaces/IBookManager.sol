// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/Book.sol";
import "../libraries/Currency.sol";
import "../libraries/OrderId.sol";
import "../libraries/Tick.sol";

interface IBookManager {
    struct BookKey {
        uint8 unitDecimals;
        Currency base;
        Currency quote;
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

    function getBookKey(BookId id) external view returns (BookKey memory);

    function getOrder(OrderId id) external view returns (Book.Order memory);

    function make(MakeParams[] calldata paramsList) external returns (OrderId[] memory ids);

    struct TakeParams {
        BookKey key;
        uint64 amount; // times 10**unitDecimals to get actual output
        uint256 maxIn;
    }

    function take(TakeParams[] calldata paramsList) external;

    struct SpendParams {
        BookKey key;
        uint256 amount;
        uint64 minOut; // times 10**unitDecimals to get actual output
    }

    function spend(SpendParams[] calldata paramsList) external;

    struct ReduceParams {
        OrderId id;
        uint64 amount;
    }

    function reduce(ReduceParams[] calldata paramsList) external;

    function cancel(uint256[] calldata ids) external;

    function claim(uint256[] calldata ids) external;

    function collect(address provider, Currency currency) external;

    function whitelist(address[] calldata provider) external;

    function delist(address[] calldata provider) external;
}
