// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./IHooks.sol";
import "../libraries/Currency.sol";

/**
 * @title IBountyPlatform
 * @notice Interface for the bounty platform contract
 */
interface IBountyPlatform {
    error NotEnoughBalance();

    /**
     * @notice Event emitted when a bounty is offered
     * @param orderId The id of the order to offer the bounty for
     * @param currency The currency of the bounty
     * @param amount The amount of the bounty
     */
    event BountyOffered(OrderId indexed orderId, Currency indexed currency, uint256 amount);

    /**
     * @notice Event emitted when a bounty is claimed
     * @param orderId The id of the order that the bounty was claimed for
     * @param claimer The address of the claimer
     */
    event BountyClaimed(OrderId indexed orderId, address indexed claimer);

    /**
     * @notice Event emitted when a bounty is canceled
     * @param orderId The id of the order that the bounty was canceled for
     */
    event BountyCanceled(OrderId indexed orderId);

    /**
     * @notice Event emitted when the default claimer is set
     * @param claimer The address of the default claimer
     */
    event SetDefaultClaimer(address indexed claimer);

    struct Bounty {
        Currency currency;
        uint88 amount;
        uint8 shifter;
    }

    /**
     * @notice Returns the default claimer
     * @return The address of the default claimer
     */
    function defaultClaimer() external view returns (address);

    /**
     * @notice Returns the balance of a specific currency
     * @param currency The currency to check the balance for
     * @return The balance of the specified currency
     */
    function balance(Currency currency) external view returns (uint256);

    /**
     * @notice Returns the bounty for a specific order
     * @param orderId The id of the order to get the bounty for
     * @return The currency and amount of the bounty
     */
    function getBounty(OrderId orderId) external view returns (Currency, uint256);

    /**
     * @notice Sets the default claimer
     * @param claimer The address to set as the default claimer
     */
    function setDefaultClaimer(address claimer) external;
}
