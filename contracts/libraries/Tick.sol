// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

type Tick is uint24;

library TickLibrary {
    function toPrice(Tick tick) internal pure returns (uint256) {
        // TODO: implement proper tick to price
        return Tick.unwrap(tick) * 1000;
    }
}
