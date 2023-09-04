// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./Math.sol";

type Tick is uint24;

library TickLibrary {
    using TickLibrary for Tick;

    error Overflow();

    uint256 private constant _PRICE_PRECISION = 10 ** 18;

    function toPrice(Tick tick) internal pure returns (uint256) {
        // TODO: implement proper tick to price
        return Tick.unwrap(tick) * 1000;
    }

    function gt(Tick a, Tick b) internal pure returns (bool) {
        return Tick.unwrap(a) > Tick.unwrap(b);
    }

    function baseToRaw(Tick tick, uint256 baseAmount, bool roundingUp) internal pure returns (uint64) {
        uint256 rawAmount = Math.divide((baseAmount * tick.toPrice()), _PRICE_PRECISION, roundingUp);
        if (rawAmount > type(uint64).max) {
            revert Overflow();
        }
        return uint64(rawAmount);
    }

    function rawToBase(Tick tick, uint64 rawAmount, bool roundingUp) internal pure returns (uint256) {
        return Math.divide(rawAmount * _PRICE_PRECISION, tick.toPrice(), roundingUp);
    }
}
