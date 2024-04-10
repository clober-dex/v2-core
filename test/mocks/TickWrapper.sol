// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "../../src/libraries/Tick.sol";

contract TickWrapper {
    function fromPrice(uint256 price) external pure returns (int24) {
        Tick tick = TickLibrary.fromPrice(price);
        return Tick.unwrap(tick);
    }

    function toPrice(int24 tick) external pure returns (uint256 price) {
        return TickLibrary.toPrice(Tick.wrap(tick));
    }
}
