// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.23;

import "../../src/libraries/TotalClaimableMap.sol";

contract TotalClaimableMapWrapper {
    mapping(uint24 => uint256) internal _totalClaimableMap;

    function add(Tick tick, uint64 n) external {
        TotalClaimableMap.add(_totalClaimableMap, tick, n);
    }

    function sub(Tick tick, uint64 n) external {
        TotalClaimableMap.sub(_totalClaimableMap, tick, n);
    }

    function get(Tick tick) external view returns (uint64) {
        return TotalClaimableMap.get(_totalClaimableMap, tick);
    }
}
