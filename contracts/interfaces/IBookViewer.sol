// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../libraries/Currency.sol";
import "../libraries/BookId.sol";
import "./IBookManager.sol";
import "./IController.sol";

interface IBookViewer {
    function bookManager() external view returns (IBookManager);

    struct Liquidity {
        Tick tick;
        uint64 depth;
    }

    function getLiquidity(BookId id, Tick from, uint256 n) external view returns (Liquidity[] memory liquidity);

    function getExpectedInput(IController.TakeOrderParams memory params)
        external
        view
        returns (uint256 takenQuoteAmount, uint256 spendBaseAmount);

    function getExpectedOutput(IController.SpendOrderParams memory params)
        external
        view
        returns (uint256 takenQuoteAmount, uint256 spendBaseAmount);
}
