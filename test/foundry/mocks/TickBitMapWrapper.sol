// SPDX-License-Identifier: -
// License: https://license.clober.io/LICENSE.pdf

pragma solidity ^0.8.0;

import "../../../contracts/libraries/TickBitmap.sol";

contract TickBitMapWrapper {
    using TickBitmap for mapping(uint256 => uint256);

    mapping(uint256 => uint256) private _tickBitmap;

    function has(uint24 value) external view returns (bool) {
        return _tickBitmap.has(value);
    }

    function isEmpty() external view returns (bool) {
        return _tickBitmap.isEmpty();
    }

    function set(uint24 value) external {
        _tickBitmap.set(value);
    }

    function clear(uint24 value) external {
        _tickBitmap.clear(value);
    }

    function lowest() external view returns (uint24) {
        return _tickBitmap.lowest();
    }

    function minGreaterThan(uint24 value) external view returns (uint24) {
        return _tickBitmap.minGreaterThan(value);
    }
}
