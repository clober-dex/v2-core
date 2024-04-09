// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "../../src/hooks/BountyPlatform.sol";

contract BountyPlatformWrapper is BountyPlatform {
    constructor(IBookManager _bookManager, address owner_, address defaultClaimer_, BountyPlatform addressToEtch)
        BountyPlatform(_bookManager, owner_, defaultClaimer_)
    {
        Hooks.validateHookPermissions(addressToEtch, getHooksCalls());
    }

    // make this a no-op in testing
    function validateHookAddress(BaseHook _this) internal pure override {}
}
