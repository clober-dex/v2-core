// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import {Math} from "./Math.sol";

type Tick is int24;

library TickLibrary {
    using Math for *;
    using TickLibrary for Tick;

    error InvalidTick();
    error InvalidPrice();
    error TickOverflow();

    int24 internal constant MAX_TICK = 2 ** 19 - 1;
    int24 internal constant MIN_TICK = -MAX_TICK;

    uint256 internal constant MIN_PRICE = 1350587;
    uint256 internal constant MAX_PRICE = 4647684107270898330752324302845848816923571339324334;

    uint256 private constant _R0 = 0xfff97272373d413259a46990;
    uint256 private constant _R1 = 0xfff2e50f5f656932ef12357c;
    uint256 private constant _R2 = 0xffe5caca7e10e4e61c3624ea;
    uint256 private constant _R3 = 0xffcb9843d60f6159c9db5883;
    uint256 private constant _R4 = 0xff973b41fa98c081472e6896;
    uint256 private constant _R5 = 0xff2ea16466c96a3843ec78b3;
    uint256 private constant _R6 = 0xfe5dee046a99a2a811c461f1;
    uint256 private constant _R7 = 0xfcbe86c7900a88aedcffc83b;
    uint256 private constant _R8 = 0xf987a7253ac413176f2b074c;
    uint256 private constant _R9 = 0xf3392b0822b70005940c7a39;
    uint256 private constant _R10 = 0xe7159475a2c29b7443b29c7f;
    uint256 private constant _R11 = 0xd097f3bdfd2022b8845ad8f7;
    uint256 private constant _R12 = 0xa9f746462d870fdf8a65dc1f;
    uint256 private constant _R13 = 0x70d869a156d2a1b890bb3df6;
    uint256 private constant _R14 = 0x31be135f97d08fd981231505;
    uint256 private constant _R15 = 0x9aa508b5b7a84e1c677de54;
    uint256 private constant _R16 = 0x5d6af8dedb81196699c329;
    uint256 private constant _R17 = 0x2216e584f5fa1ea92604;
    uint256 private constant _R18 = 0x48a170391f7dc42;
    uint256 private constant _R19 = 0x149b34;

    function validateTick(Tick tick) internal pure {
        if (Tick.unwrap(tick) > MAX_TICK || Tick.unwrap(tick) < MIN_TICK) revert InvalidTick();
    }

    modifier validatePrice(uint256 price) {
        if (price > MAX_PRICE || price < MIN_PRICE) revert InvalidPrice();
        _;
    }

    function fromPrice(uint256 price) internal pure validatePrice(price) returns (Tick) {
        unchecked {
            int24 tick = int24((int256(price).lnWad() * 42951820407860) / 2 ** 128);
            if (toPrice(Tick.wrap(tick)) > price) return Tick.wrap(tick - 1);
            return Tick.wrap(tick);
        }
    }

    function toPrice(Tick tick) internal pure returns (uint256 price) {
        validateTick(tick);
        int24 tickValue = Tick.unwrap(tick);
        uint256 absTick = uint24(tickValue < 0 ? -tickValue : tickValue);

        unchecked {
            if (absTick & 0x1 != 0) price = _R0;
            else price = 1 << 96;
            if (absTick & 0x2 != 0) price = (price * _R1) >> 96;
            if (absTick & 0x4 != 0) price = (price * _R2) >> 96;
            if (absTick & 0x8 != 0) price = (price * _R3) >> 96;
            if (absTick & 0x10 != 0) price = (price * _R4) >> 96;
            if (absTick & 0x20 != 0) price = (price * _R5) >> 96;
            if (absTick & 0x40 != 0) price = (price * _R6) >> 96;
            if (absTick & 0x80 != 0) price = (price * _R7) >> 96;
            if (absTick & 0x100 != 0) price = (price * _R8) >> 96;
            if (absTick & 0x200 != 0) price = (price * _R9) >> 96;
            if (absTick & 0x400 != 0) price = (price * _R10) >> 96;
            if (absTick & 0x800 != 0) price = (price * _R11) >> 96;
            if (absTick & 0x1000 != 0) price = (price * _R12) >> 96;
            if (absTick & 0x2000 != 0) price = (price * _R13) >> 96;
            if (absTick & 0x4000 != 0) price = (price * _R14) >> 96;
            if (absTick & 0x8000 != 0) price = (price * _R15) >> 96;
            if (absTick & 0x10000 != 0) price = (price * _R16) >> 96;
            if (absTick & 0x20000 != 0) price = (price * _R17) >> 96;
            if (absTick & 0x40000 != 0) price = (price * _R18) >> 96;
        }
        if (tickValue > 0) price = 0x1000000000000000000000000000000000000000000000000 / price;
    }

    function gt(Tick a, Tick b) internal pure returns (bool) {
        return Tick.unwrap(a) > Tick.unwrap(b);
    }

    function baseToQuote(Tick tick, uint256 base, bool roundingUp) internal pure returns (uint256) {
        return Math.divide((base * tick.toPrice()), 1 << 96, roundingUp);
    }

    function quoteToBase(Tick tick, uint256 quote, bool roundingUp) internal pure returns (uint256) {
        // @dev quote = unit(uint64) * unitSize(uint64) < 2^96
        //      We don't need to check overflow here
        return Math.divide(quote << 96, tick.toPrice(), roundingUp);
    }
}
