// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Currency, CurrencyLibrary} from "./Currency.sol";

library CurrencyDelta {
    // uint256(keccak256("CurrencyDelta")) + 1
    uint256 internal constant CURRENCY_DELTA_SLOT = 0x95b400a0305233758f18c75aa62cbbb5d6882951dd55f1407390ee7b6924e26f;

    function get(address locker, Currency currency) internal view returns (int256 delta) {
        assembly {
            mstore(0x14, currency)
            mstore(0x00, locker)
            delta := tload(keccak256(0x0c, 0x28))
        }
    }

    function add(address locker, Currency currency, int256 delta) internal returns (int256 result) {
        assembly {
            mstore(0x14, currency)
            mstore(0x00, locker)
            let slot := keccak256(0x0c, 0x28)
            result := add(tload(slot), delta)
            tstore(slot, result)
        }
    }
}
