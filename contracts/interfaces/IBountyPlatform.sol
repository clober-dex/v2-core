// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./IHooks.sol";
import "../libraries/Currency.sol";

interface IBountyPlatform {
    error NotEnoughBalance();

    event BountyOffered(OrderId indexed orderId, Currency indexed curreny, uint256 amount);
    event BountyClaimed(OrderId indexed orderId, address indexed claimer);
    event BountyCanceled(OrderId indexed orderId);
    event SetDefaultClaimer(address indexed claimer);

    struct Bounty {
        Currency currency;
        uint88 amount;
        uint8 shifter;
    }

    function defaultClaimer() external view returns (address);

    function balance(Currency currency) external view returns (uint256);

    function getBounty(OrderId orderId) external view returns (Currency, uint256);

    function setDefaultClaimer(address claimer) external;
}
