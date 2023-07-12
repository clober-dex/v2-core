// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/CurrencyLibrary.sol";

interface IBookManager {
    struct BookKey {
        Currency base;
        uint8 baseUnitDecimals;
        Currency quote;
        uint8 quoteUnitDecimals;
        int24 makerFee;
        uint24 takerFee;
        uint24 tickSpacing;
    }

    struct MakeParams {
        BookKey key;
        /// @notice The limit order service provider address to collect fees
        address provider;
        uint24 priceIndex;
        uint64 amount;
    }

    function make(MakeParams[] memory paramsList) external returns (uint256 orderIndex);

    struct TakeParams {
        BookKey key;
        uint64 amount;
    }

    function take(TakeParams[] memory paramsList) external;

    struct ReduceParams {
        BookKey key;
        uint256 orderIndex;
    }

    function reduce(ReduceParams[] memory paramsList) external;

    struct ClaimParams {
        BookKey key;
        uint256 orderIndex;
    }

    function claim(ClaimParams[] memory paramsList) external;
}
