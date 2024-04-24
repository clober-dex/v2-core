// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../mocks/CurrencyDeltaWrapper.sol";
import "../../../src/libraries/Currency.sol";

contract CurrencyDeltaTest is Test {
    CurrencyDeltaWrapper public currencyDelta;

    address internal ADDRESS1 = address(0);
    address internal ADDRESS2 = address(1);
    address internal ADDRESS3 = address(0x8000000000000000000000000000000000000000);

    function setUp() public {
        currencyDelta = new CurrencyDeltaWrapper();
    }

    function testAddDelta() public {
        int256 d1 = currencyDelta.get(ADDRESS1, ADDRESS1);
        int256 d2 = currencyDelta.get(ADDRESS1, ADDRESS2);
        int256 d3 = currencyDelta.get(ADDRESS1, ADDRESS3);
        int256 d4 = currencyDelta.get(ADDRESS2, ADDRESS1);
        int256 d5 = currencyDelta.get(ADDRESS2, ADDRESS2);
        int256 d6 = currencyDelta.get(ADDRESS2, ADDRESS3);
        int256 d7 = currencyDelta.get(ADDRESS3, ADDRESS1);
        int256 d8 = currencyDelta.get(ADDRESS3, ADDRESS2);
        int256 d9 = currencyDelta.get(ADDRESS3, ADDRESS3);

        assertEq(d1, 0);
        assertEq(d2, 0);
        assertEq(d3, 0);
        assertEq(d4, 0);
        assertEq(d5, 0);
        assertEq(d6, 0);
        assertEq(d7, 0);
        assertEq(d8, 0);
        assertEq(d9, 0);

        currencyDelta.add(ADDRESS1, ADDRESS1, -4);
        currencyDelta.add(ADDRESS1, ADDRESS2, -3);
        currencyDelta.add(ADDRESS1, ADDRESS3, -2);
        currencyDelta.add(ADDRESS2, ADDRESS1, -1);
        currencyDelta.add(ADDRESS2, ADDRESS2, 1);
        currencyDelta.add(ADDRESS2, ADDRESS3, 2);
        currencyDelta.add(ADDRESS3, ADDRESS1, 3);
        currencyDelta.add(ADDRESS3, ADDRESS2, 4);
        currencyDelta.add(ADDRESS3, ADDRESS3, 5);

        d1 = currencyDelta.get(ADDRESS1, ADDRESS1);
        d2 = currencyDelta.get(ADDRESS1, ADDRESS2);
        d3 = currencyDelta.get(ADDRESS1, ADDRESS3);
        d4 = currencyDelta.get(ADDRESS2, ADDRESS1);
        d5 = currencyDelta.get(ADDRESS2, ADDRESS2);
        d6 = currencyDelta.get(ADDRESS2, ADDRESS3);
        d7 = currencyDelta.get(ADDRESS3, ADDRESS1);
        d8 = currencyDelta.get(ADDRESS3, ADDRESS2);
        d9 = currencyDelta.get(ADDRESS3, ADDRESS3);

        assertEq(d1, -4);
        assertEq(d2, -3);
        assertEq(d3, -2);
        assertEq(d4, -1);
        assertEq(d5, 1);
        assertEq(d6, 2);
        assertEq(d7, 3);
        assertEq(d8, 4);
        assertEq(d9, 5);
    }
}
