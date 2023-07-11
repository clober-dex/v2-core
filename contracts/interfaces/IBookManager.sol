// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../libraries/CurrencyLibrary.sol";

interface IBookManager {
    struct BookKey {
        Currency base;
        uint8 baseUnitDecimals;
        Currency quote;
        uint8 quoteUnitDecimals;
        uint24 makerFee;
        uint24 takerFee;
        uint24 tickSpacing;
    }
}
