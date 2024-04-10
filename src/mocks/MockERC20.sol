// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC20Permit, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockERC20 is ERC20Permit {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) ERC20Permit(name_) {
        _decimals = decimals_;
    }

    function mint(address account, uint256 value) external {
        _mint(account, value);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
