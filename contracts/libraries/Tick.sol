// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./Math.sol";

type Tick is int24;

library TickLibrary {
    using TickLibrary for Tick;

    error InvalidTick();
    error InvalidPrice();
    error TickOverflow();

    uint256 private constant _PRICE_PRECISION = 10 ** 18;

    int24 private constant _MAX_TICK = 887272;
    int24 private constant _MIN_TICK = -_MAX_TICK;
    uint256 private constant _MIN_PRICE = 1;
    uint256 private constant _MAX_PRICE = 1;
    // TODO: fill the constants
    uint256 private constant _R0 = 1;
    uint256 private constant _R1 = 1;
    uint256 private constant _R2 = 1;
    uint256 private constant _R3 = 1;
    uint256 private constant _R4 = 1;
    uint256 private constant _R5 = 1;
    uint256 private constant _R6 = 1;
    uint256 private constant _R7 = 1;
    uint256 private constant _R8 = 1;
    uint256 private constant _R9 = 1;
    uint256 private constant _R10 = 1;
    uint256 private constant _R11 = 1;
    uint256 private constant _R12 = 1;
    uint256 private constant _R13 = 1;
    uint256 private constant _R14 = 1;
    uint256 private constant _R15 = 1;
    uint256 private constant _R16 = 1;
    uint256 private constant _R17 = 1;
    uint256 private constant _R18 = 1;
    uint256 private constant _R19 = 1;
    uint256 private constant _R20 = 1;

    function validate(Tick tick) internal pure {
        if (Tick.unwrap(tick) > _MAX_TICK) {
            revert InvalidTick();
        }
    }

    function fromPrice(uint256 price, bool roundingUp) internal pure returns (Tick tick, uint256 correctedPrice) {
        if (price < _MIN_PRICE || price >= _MAX_PRICE) {
            revert InvalidPrice();
        }
        int24 index = 0;
        uint256 _correctedPrice = _MIN_PRICE;
        uint256 shiftedPrice = (price + 1) << 64;

        unchecked {
            if (shiftedPrice > _R19 * _correctedPrice) {
                index = index | 0x80000;
                _correctedPrice = (_correctedPrice * _R19) >> 64;
            }
            if (shiftedPrice > _R18 * _correctedPrice) {
                index = index | 0x40000;
                _correctedPrice = (_correctedPrice * _R18) >> 64;
            }
            if (shiftedPrice > _R17 * _correctedPrice) {
                index = index | 0x20000;
                _correctedPrice = (_correctedPrice * _R17) >> 64;
            }
            if (shiftedPrice > _R16 * _correctedPrice) {
                index = index | 0x10000;
                _correctedPrice = (_correctedPrice * _R16) >> 64;
            }
            if (shiftedPrice > _R15 * _correctedPrice) {
                index = index | 0x8000;
                _correctedPrice = (_correctedPrice * _R15) >> 64;
            }
            if (shiftedPrice > _R14 * _correctedPrice) {
                index = index | 0x4000;
                _correctedPrice = (_correctedPrice * _R14) >> 64;
            }
            if (shiftedPrice > _R13 * _correctedPrice) {
                index = index | 0x2000;
                _correctedPrice = (_correctedPrice * _R13) >> 64;
            }
            if (shiftedPrice > _R12 * _correctedPrice) {
                index = index | 0x1000;
                _correctedPrice = (_correctedPrice * _R12) >> 64;
            }
            if (shiftedPrice > _R11 * _correctedPrice) {
                index = index | 0x0800;
                _correctedPrice = (_correctedPrice * _R11) >> 64;
            }
            if (shiftedPrice > _R10 * _correctedPrice) {
                index = index | 0x0400;
                _correctedPrice = (_correctedPrice * _R10) >> 64;
            }
            if (shiftedPrice > _R9 * _correctedPrice) {
                index = index | 0x0200;
                _correctedPrice = (_correctedPrice * _R9) >> 64;
            }
            if (shiftedPrice > _R8 * _correctedPrice) {
                index = index | 0x0100;
                _correctedPrice = (_correctedPrice * _R8) >> 64;
            }
            if (shiftedPrice > _R7 * _correctedPrice) {
                index = index | 0x0080;
                _correctedPrice = (_correctedPrice * _R7) >> 64;
            }
            if (shiftedPrice > _R6 * _correctedPrice) {
                index = index | 0x0040;
                _correctedPrice = (_correctedPrice * _R6) >> 64;
            }
            if (shiftedPrice > _R5 * _correctedPrice) {
                index = index | 0x0020;
                _correctedPrice = (_correctedPrice * _R5) >> 64;
            }
            if (shiftedPrice > _R4 * _correctedPrice) {
                index = index | 0x0010;
                _correctedPrice = (_correctedPrice * _R4) >> 64;
            }
            if (shiftedPrice > _R3 * _correctedPrice) {
                index = index | 0x0008;
                _correctedPrice = (_correctedPrice * _R3) >> 64;
            }
            if (shiftedPrice > _R2 * _correctedPrice) {
                index = index | 0x0004;
                _correctedPrice = (_correctedPrice * _R2) >> 64;
            }
            if (shiftedPrice > _R1 * _correctedPrice) {
                index = index | 0x0002;
                _correctedPrice = (_correctedPrice * _R1) >> 64;
            }
            if (shiftedPrice > _R0 * _correctedPrice) {
                index = index | 0x0001;
                _correctedPrice = (_correctedPrice * _R0) >> 64;
            }
        }
        if (roundingUp && _correctedPrice < price) {
            unchecked {
                index += 1;
            }
            correctedPrice = toPrice(Tick.wrap(index));
        } else {
            correctedPrice = _correctedPrice;
        }
        tick = Tick.wrap(index);
    }

    function toPrice(Tick tick) internal pure returns (uint256 price) {
        tick.validate();
        int24 tickValue = Tick.unwrap(tick);
        uint256 absTick = uint24(tickValue < 0 ? -tickValue : tickValue);
        price = _PRICE_PRECISION;
        unchecked {
            if (absTick & 0x80000 != 0) price = (price * _R19) >> 64;
            if (absTick & 0x40000 != 0) price = (price * _R18) >> 64;
            if (absTick & 0x20000 != 0) price = (price * _R17) >> 64;
            if (absTick & 0x10000 != 0) price = (price * _R16) >> 64;
            if (absTick & 0x8000 != 0) price = (price * _R15) >> 64;
            if (absTick & 0x4000 != 0) price = (price * _R14) >> 64;
            if (absTick & 0x2000 != 0) price = (price * _R13) >> 64;
            if (absTick & 0x1000 != 0) price = (price * _R12) >> 64;
            if (absTick & 0x800 != 0) price = (price * _R11) >> 64;
            if (absTick & 0x400 != 0) price = (price * _R10) >> 64;
            if (absTick & 0x200 != 0) price = (price * _R9) >> 64;
            if (absTick & 0x100 != 0) price = (price * _R8) >> 64;
            if (absTick & 0x80 != 0) price = (price * _R7) >> 64;
            if (absTick & 0x40 != 0) price = (price * _R6) >> 64;
            if (absTick & 0x20 != 0) price = (price * _R5) >> 64;
            if (absTick & 0x10 != 0) price = (price * _R4) >> 64;
            if (absTick & 0x8 != 0) price = (price * _R3) >> 64;
            if (absTick & 0x4 != 0) price = (price * _R2) >> 64;
            if (absTick & 0x2 != 0) price = (price * _R1) >> 64;
            if (absTick & 0x1 != 0) price = (price * _R0) >> 64;
            if (tickValue < 0) price = _PRICE_PRECISION * _PRICE_PRECISION / price;
        }
    }

    function gt(Tick a, Tick b) internal pure returns (bool) {
        return Tick.unwrap(a) > Tick.unwrap(b);
    }

    function baseToRaw(Tick tick, uint256 baseAmount, bool roundingUp) internal pure returns (uint64) {
        uint256 rawAmount = Math.divide((baseAmount * tick.toPrice()), _PRICE_PRECISION, roundingUp);
        if (rawAmount > type(uint64).max) {
            revert TickOverflow();
        }
        return uint64(rawAmount);
    }

    function rawToBase(Tick tick, uint64 rawAmount, bool roundingUp) internal pure returns (uint256) {
        return Math.divide(rawAmount * _PRICE_PRECISION, tick.toPrice(), roundingUp);
    }
}
