// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../src/libraries/CurrencyDelta.sol";
import "../../src/libraries/Currency.sol";

contract CurrencyDeltaWrapper {
    function get(address locker, address currency) external view returns (int256) {
        return CurrencyDelta.get(locker, Currency.wrap(currency));
    }

    function add(address locker, address currency, int256 delta) external returns (int256) {
        return CurrencyDelta.add(locker, Currency.wrap(currency), delta);
    }
}
