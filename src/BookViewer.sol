// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.20;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IBookManager} from "./interfaces/IBookManager.sol";
import {IBookViewer} from "./interfaces/IBookViewer.sol";
import {IController} from "./interfaces/IController.sol";
import {SignificantBit} from "./libraries/SignificantBit.sol";
import {Math} from "./libraries/Math.sol";
import {Lockers} from "./libraries/Lockers.sol";
import {BookId} from "./libraries/BookId.sol";
import {Tick, TickLibrary} from "./libraries/Tick.sol";
import {FeePolicy, FeePolicyLibrary} from "./libraries/FeePolicy.sol";

contract BookViewer is IBookViewer {
    using SafeCast for *;
    using TickLibrary for *;
    using Math for uint256;
    using SignificantBit for uint256;
    using FeePolicyLibrary for FeePolicy;

    IBookManager public immutable bookManager;

    constructor(IBookManager bookManager_) {
        bookManager = bookManager_;
    }

    function getLiquidity(BookId id, Tick tick, uint256 n) external view returns (Liquidity[] memory liquidity) {
        liquidity = new Liquidity[](n);
        if (bookManager.getDepth(id, tick) == 0) tick = bookManager.maxLessThan(id, tick);
        uint256 i;
        while (i < n) {
            if (Tick.unwrap(tick) == type(int24).min) break;
            liquidity[i] = Liquidity({tick: tick, depth: bookManager.getDepth(id, tick)});
            tick = bookManager.maxLessThan(id, tick);
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(liquidity, i)
        }
    }

    function getExpectedInput(IController.TakeOrderParams memory params)
        external
        view
        returns (uint256 takenQuoteAmount, uint256 spentBaseAmount)
    {
        IBookManager.BookKey memory key = bookManager.getBookKey(params.id);

        if (bookManager.isEmpty(params.id)) return (0, 0);

        Tick tick = bookManager.getHighest(params.id);

        while (Tick.unwrap(tick) > type(int24).min) {
            unchecked {
                if (params.limitPrice > tick.toPrice()) break;
                uint256 maxAmount;
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = key.takerPolicy.calculateOriginalAmount(params.quoteAmount - takenQuoteAmount, true);
                } else {
                    maxAmount = params.quoteAmount - takenQuoteAmount;
                }
                maxAmount = maxAmount.divide(key.unitSize, true);

                if (maxAmount == 0) break;
                uint256 currentDepth = bookManager.getDepth(params.id, tick);
                uint256 quoteAmount = (currentDepth > maxAmount ? maxAmount : currentDepth) * key.unitSize;
                uint256 baseAmount = tick.quoteToBase(quoteAmount, true);
                if (key.takerPolicy.usesQuote()) {
                    quoteAmount = uint256(int256(quoteAmount) - key.takerPolicy.calculateFee(quoteAmount, false));
                } else {
                    baseAmount = uint256(baseAmount.toInt256() + key.takerPolicy.calculateFee(baseAmount, false));
                }
                if (quoteAmount == 0) break;

                takenQuoteAmount += quoteAmount;
                spentBaseAmount += baseAmount;
                if (params.quoteAmount <= takenQuoteAmount) break;
                tick = bookManager.maxLessThan(params.id, tick);
            }
        }
    }

    function getExpectedOutput(IController.SpendOrderParams memory params)
        external
        view
        returns (uint256 takenQuoteAmount, uint256 spentBaseAmount)
    {
        IBookManager.BookKey memory key = bookManager.getBookKey(params.id);

        if (bookManager.isEmpty(params.id)) return (0, 0);

        Tick tick = bookManager.getHighest(params.id);

        unchecked {
            while (spentBaseAmount <= params.baseAmount && Tick.unwrap(tick) > type(int24).min) {
                if (params.limitPrice > tick.toPrice()) break;
                uint256 maxAmount;
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = params.baseAmount - spentBaseAmount;
                } else {
                    maxAmount = key.takerPolicy.calculateOriginalAmount(params.baseAmount - spentBaseAmount, false);
                }
                maxAmount = tick.baseToQuote(maxAmount, false) / key.unitSize;

                if (maxAmount == 0) break;
                uint256 currentDepth = bookManager.getDepth(params.id, tick);
                uint256 quoteAmount = (currentDepth > maxAmount ? maxAmount : currentDepth) * key.unitSize;
                uint256 baseAmount = tick.quoteToBase(quoteAmount, true);
                if (key.takerPolicy.usesQuote()) {
                    quoteAmount = uint256(int256(quoteAmount) - key.takerPolicy.calculateFee(quoteAmount, false));
                } else {
                    baseAmount = uint256(baseAmount.toInt256() + key.takerPolicy.calculateFee(baseAmount, false));
                }
                if (baseAmount == 0) break;

                takenQuoteAmount += quoteAmount;
                spentBaseAmount += baseAmount;
                tick = bookManager.maxLessThan(params.id, tick);
            }
        }
    }
}
