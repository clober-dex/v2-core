// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./Math.sol";

type Tick is int24;

library TickLibrary {
    using Math for uint256;
    using TickLibrary for Tick;

    error InvalidTick();
    error InvalidPrice();
    error TickOverflow();

    int24 internal constant MAX_TICK = 2 ** 19 - 1;
    int24 internal constant MIN_TICK = -MAX_TICK;

    uint256 internal constant MIN_PRICE = 5800731190957938;
    uint256 internal constant MAX_PRICE = 19961636804996334433808922353085948875386438476189866322430503;

    uint256 private constant _R0 = 0xfff97272373d413259a46990580e2139; // 2^128 / r^(2^0)
    uint256 private constant _R1 = 0xfff2e50f5f656932ef12357cf3c7fdcb;
    uint256 private constant _R2 = 0xffe5caca7e10e4e61c3624eaa0941ccf;
    uint256 private constant _R3 = 0xffcb9843d60f6159c9db58835c926643;
    uint256 private constant _R4 = 0xff973b41fa98c081472e6896dfb254bf;
    uint256 private constant _R5 = 0xff2ea16466c96a3843ec78b326b52860;
    uint256 private constant _R6 = 0xfe5dee046a99a2a811c461f1969c3052;
    uint256 private constant _R7 = 0xfcbe86c7900a88aedcffc83b479aa3a3;
    uint256 private constant _R8 = 0xf987a7253ac413176f2b074cf7815e53;
    uint256 private constant _R9 = 0xf3392b0822b70005940c7a398e4b70f2;
    uint256 private constant _R10 = 0xe7159475a2c29b7443b29c7fa6e889d8;
    uint256 private constant _R11 = 0xd097f3bdfd2022b8845ad8f792aa5825;
    uint256 private constant _R12 = 0xa9f746462d870fdf8a65dc1f90e061e4;
    uint256 private constant _R13 = 0x70d869a156d2a1b890bb3df62baf32f6;
    uint256 private constant _R14 = 0x31be135f97d08fd981231505542fcfa5;
    uint256 private constant _R15 = 0x9aa508b5b7a84e1c677de54f3e99bc8;
    uint256 private constant _R16 = 0x5d6af8dedb81196699c329225ee604;
    uint256 private constant _R17 = 0x2216e584f5fa1ea926041bedfe97;
    uint256 private constant _R18 = 0x48a170391f7dc42444e8fa2;

    function validateTick(Tick tick) internal pure {
        if (Tick.unwrap(tick) > MAX_TICK || Tick.unwrap(tick) < MIN_TICK) revert InvalidTick();
    }

    modifier validatePrice(uint256 price) {
        if (price > MAX_PRICE || price < MIN_PRICE) revert InvalidPrice();
        _;
    }

    function toTick(uint24 x) internal pure returns (Tick t) {
        assembly {
            t := sub(x, 0x800000)
        }
    }

    function toUint24(Tick tick) internal pure returns (uint24 r) {
        assembly {
            r := add(tick, 0x800000)
        }
    }

    function fromPrice(uint256 price) internal pure validatePrice(price) returns (Tick) {
        int256 log = price.log2();
        int256 tick = log / 49089913871092318234424474366155889;
        int256 tickLow = (
            log - int256(uint256((price >> 128 == 0) ? 49089913871092318234424474366155887 : 84124744249948177485425))
        ) / 49089913871092318234424474366155889;

        if (tick == tickLow) return Tick.wrap(int24(tick));

        if (toPrice(Tick.wrap(int24(tick))) <= price) return Tick.wrap(int24(tick));

        return Tick.wrap(int24(tickLow));
    }

    function toPrice(Tick tick) internal pure returns (uint256 price) {
        validateTick(tick);
        int24 tickValue = Tick.unwrap(tick);
        uint256 absTick = uint24(tickValue < 0 ? -tickValue : tickValue);

        unchecked {
            if (absTick & 0x1 != 0) price = _R0;
            else price = 1 << 128;
            if (absTick & 0x2 != 0) price = (price * _R1) >> 128;
            if (absTick & 0x4 != 0) price = (price * _R2) >> 128;
            if (absTick & 0x8 != 0) price = (price * _R3) >> 128;
            if (absTick & 0x10 != 0) price = (price * _R4) >> 128;
            if (absTick & 0x20 != 0) price = (price * _R5) >> 128;
            if (absTick & 0x40 != 0) price = (price * _R6) >> 128;
            if (absTick & 0x80 != 0) price = (price * _R7) >> 128;
            if (absTick & 0x100 != 0) price = (price * _R8) >> 128;
            if (absTick & 0x200 != 0) price = (price * _R9) >> 128;
            if (absTick & 0x400 != 0) price = (price * _R10) >> 128;
            if (absTick & 0x800 != 0) price = (price * _R11) >> 128;
            if (absTick & 0x1000 != 0) price = (price * _R12) >> 128;
            if (absTick & 0x2000 != 0) price = (price * _R13) >> 128;
            if (absTick & 0x4000 != 0) price = (price * _R14) >> 128;
            if (absTick & 0x8000 != 0) price = (price * _R15) >> 128;
            if (absTick & 0x10000 != 0) price = (price * _R16) >> 128;
            if (absTick & 0x20000 != 0) price = (price * _R17) >> 128;
            if (absTick & 0x40000 != 0) price = (price * _R18) >> 128;
        }
        if (tickValue > 0) price = type(uint256).max / price;
    }

    function gt(Tick a, Tick b) internal pure returns (bool) {
        return Tick.unwrap(a) > Tick.unwrap(b);
    }

    function baseToQuote(Tick tick, uint256 base, bool roundingUp) internal pure returns (uint256) {
        return Math.divide((base * tick.toPrice()), 1 << 128, roundingUp);
    }

    function quoteToBase(Tick tick, uint256 quote, bool roundingUp) internal pure returns (uint256) {
        // @dev quote = raw(uint64) * unit(uint64) < 2^128
        //      We don't need to check overflow here
        return Math.divide(quote << 128, tick.toPrice(), roundingUp);
    }
}
