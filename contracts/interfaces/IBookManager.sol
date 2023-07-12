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

    function make(MakeParams[] memory paramsList) external returns (uint256 id);

    struct TakeParams {
        BookKey key;
        uint64 amount;
    }

    function take(TakeParams[] memory paramsList) external;

    struct ReduceParams {
        uint256 id;
        uint64 amount;
    }

    function reduce(ReduceParams[] memory paramsList) external;

    function cancel(uint256[] memory ids) external;

    function claim(uint256[] memory ids) external;

    function collect(address provider, Currency currency) external;

    function assign(address provider, uint8 status) external;
}
