// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./Tick.sol";

library MockHeap {
    using MockHeap for Core;

    struct Core {
        uint256 data;
    }

    function init(Core storage core) internal {}

    function has(Core storage core, Tick tick) internal view returns (bool) {}

    function isEmpty(Core storage core) internal view returns (bool) {}

    function getRootWordAndHeap(Core storage core) internal view returns (uint256 word, uint256[] memory heap) {}

    function root(Core storage core) internal view returns (Tick) {}

    function push(Core storage core, Tick tick) internal {}

    function pop(Core storage core) internal {}
}
