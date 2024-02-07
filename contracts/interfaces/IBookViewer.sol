// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../libraries/Currency.sol";
import "../libraries/BookId.sol";
import "./IBookManager.sol";

interface IBookViewer {
    function bookManager() external view returns (IBookManager);

    function baseURI() external view returns (string memory);

    function contractURI() external view returns (string memory);

    function defaultProvider() external view returns (address);

    function currencyDelta(address locker, Currency currency) external view returns (int256);

    function reservesOf(Currency currency) external view returns (uint256);

    function getBookKey(BookId id) external view returns (IBookManager.BookKey memory);

    function isWhitelisted(address provider) external view returns (bool);

    function tokenOwed(address provider, Currency currency) external view returns (uint256);

    function getLock(uint256 i) external view returns (address locker, address lockCaller);

    function getLockData() external view returns (uint128 length, uint128 nonzeroDeltaCount);

    struct Liquidity {
        Tick tick;
        uint64 depth;
    }

    function getLiquidity(BookId id, Tick from, uint256 n) external view returns (Liquidity[] memory liquidity);
}
