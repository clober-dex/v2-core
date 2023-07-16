// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/Currency.sol";
import "../libraries/OrderId.sol";
import "../libraries/Tick.sol";

interface IBookManager {
    struct BookKey {
        uint8 unitDecimals;
        Currency base;
        Currency quote;
        int24 makerFee;
        uint24 takerFee;
        uint24 tickSpacing;
    }

    struct MakeParams {
        BookKey key;
        address user;
        Tick tick;
        uint64 amount; // times 10**unitDecimals to get actual bid amount
        /// @notice The limit order service provider address to collect fees
        address provider;
        uint64 bounty;
    }

    function make(MakeParams[] memory paramsList) external returns (OrderId[] memory ids);

    struct TakeParams {
        BookKey key;
        uint64 amount; // times 10**unitDecimals to get actual output
        uint256 maxIn;
    }

    function take(TakeParams[] memory paramsList) external;

    struct SpendParams {
        BookKey key;
        uint256 amount;
        uint64 minOut; // times 10**unitDecimals to get actual output
    }

    function spend(SpendParams[] memory paramsList) external;

    struct ReduceParams {
        OrderId id;
        uint64 amount;
    }

    function reduce(ReduceParams[] memory paramsList) external;

    function cancel(uint256[] memory ids) external;

    function claim(uint256[] memory ids) external;

    function collect(address provider, Currency currency) external;

    function whitelist(address provider) external;

    function blacklist(address provider) external;

    function delist(address provider) external;
}
