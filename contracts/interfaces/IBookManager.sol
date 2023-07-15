// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/Currency.sol";
import "../libraries/OrderId.sol";

interface IBookManager {
    struct BookKey {
        Currency base;
        uint8 unitDecimals;
        Currency quote;
        int24 makerFee;
        uint24 takerFee;
        uint24 tickSpacing;
    }

    struct MakeParams {
        BookKey key;
        /// @notice The limit order service provider address to collect fees
        address provider;
        uint24 tick;
        uint64 amount;
    }

    function make(MakeParams[] memory paramsList) external returns (OrderId[] ids);

    struct TakeParams {
        BookKey key;
        uint64 amount;
        uint64 maxIn;
    }

    function take(TakeParams[] memory paramsList) external;

    struct SpendParams {
        BookKey key;
        uint64 amount;
        uint64 minOut;
    }

    function spend(SpendParams[] memory paramsList) external;

    struct ReduceParams {
        uint256 id;
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
