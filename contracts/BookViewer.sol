// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "./interfaces/IBookViewer.sol";
import "./libraries/Lockers.sol";
import "./interfaces/IController.sol";

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
        if (bookManager.getDepth(id, tick) == 0) tick = bookManager.minGreaterThan(id, tick);
        for (uint256 i = 0; i < n; ++i) {
            if (Tick.unwrap(tick) == type(int24).min) break;
            liquidity[i] = Liquidity({tick: tick, depth: bookManager.getDepth(id, tick)});
            tick = bookManager.minGreaterThan(id, tick);
        }
    }

    function getExpectedInput(IController.TakeOrderParams memory params)
        external
        view
        returns (uint256 takenQuoteAmount, uint256 spendBaseAmount)
    {
        IBookManager.BookKey memory key = bookManager.getBookKey(params.id);

        if (bookManager.isEmpty(params.id)) return (0, 0);

        Tick tick = bookManager.getLowest(params.id);

        while (Tick.unwrap(tick) > type(int24).min) {
            unchecked {
                if (params.limitPrice < tick.toPrice()) break;
                uint256 maxAmount;
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = key.takerPolicy.calculateOriginalAmount(params.quoteAmount - takenQuoteAmount, true);
                } else {
                    maxAmount = params.quoteAmount - takenQuoteAmount;
                }
                maxAmount = maxAmount.divide(key.unit, true);

                if (maxAmount == 0) break;
                uint256 currentDepth = bookManager.getDepth(params.id, tick);
                uint256 quoteAmount = (currentDepth > maxAmount ? maxAmount : currentDepth) * key.unit;
                uint256 baseAmount = tick.quoteToBase(quoteAmount, true);
                if (key.takerPolicy.usesQuote()) {
                    quoteAmount = uint256(int256(quoteAmount) - key.takerPolicy.calculateFee(quoteAmount, false));
                } else {
                    baseAmount = uint256(baseAmount.toInt256() + key.takerPolicy.calculateFee(baseAmount, false));
                }
                if (quoteAmount == 0) break;

                takenQuoteAmount += quoteAmount;
                spendBaseAmount += baseAmount;
                if (params.quoteAmount <= takenQuoteAmount) break;
                tick = bookManager.minGreaterThan(params.id, tick);
            }
        }
    }

    function getExpectedOutput(IController.SpendOrderParams memory params)
        external
        view
        returns (uint256 takenQuoteAmount, uint256 spendBaseAmount)
    {
        IBookManager.BookKey memory key = bookManager.getBookKey(params.id);

        if (bookManager.isEmpty(params.id)) return (0, 0);

        Tick tick = bookManager.getLowest(params.id);

        unchecked {
            while (spendBaseAmount <= params.baseAmount && Tick.unwrap(tick) > type(int24).min) {
                if (params.limitPrice < tick.toPrice()) break;
                uint256 maxAmount;
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = params.baseAmount - spendBaseAmount;
                } else {
                    maxAmount = key.takerPolicy.calculateOriginalAmount(params.baseAmount - spendBaseAmount, false);
                }
                maxAmount = tick.baseToQuote(maxAmount, false) / key.unit;

                if (maxAmount == 0) break;
                uint256 currentDepth = bookManager.getDepth(params.id, tick);
                uint256 quoteAmount = (currentDepth > maxAmount ? maxAmount : currentDepth) * key.unit;
                uint256 baseAmount = tick.quoteToBase(quoteAmount, true);
                if (key.takerPolicy.usesQuote()) {
                    quoteAmount = uint256(int256(quoteAmount) - key.takerPolicy.calculateFee(quoteAmount, false));
                } else {
                    baseAmount = uint256(baseAmount.toInt256() + key.takerPolicy.calculateFee(baseAmount, false));
                }
                if (baseAmount == 0) break;

                takenQuoteAmount += quoteAmount;
                spendBaseAmount += baseAmount;
                tick = bookManager.minGreaterThan(params.id, tick);
            }
        }
    }
}
