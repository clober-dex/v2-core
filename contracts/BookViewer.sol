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

    IBookManager public immutable override bookManager;

    constructor(IBookManager bookManager_) {
        bookManager = bookManager_;
    }

    function baseURI() external view returns (string memory) {
        return _loadString(bytes32(uint256(10)));
    }

    function contractURI() external view returns (string memory) {
        return _loadString(bytes32(uint256(11)));
    }

    function defaultProvider() external view returns (address) {
        return address(uint160(uint256(bookManager.load(bytes32(uint256(12))))));
    }

    function currencyDelta(address locker, Currency currency) external view returns (int256) {
        return int256(
            uint256(
                bookManager.load(keccak256(abi.encode(currency, keccak256(abi.encode(locker, bytes32(uint256(13)))))))
            )
        );
    }

    function reservesOf(Currency currency) external view returns (uint256) {
        return uint256(bookManager.load(keccak256(abi.encode(currency, bytes32(uint256(14))))));
    }

    function getBookKey(BookId id) public view returns (IBookManager.BookKey memory) {
        bytes memory data = bookManager.load(keccak256(abi.encode(id, bytes32(uint256(15)))), 3);
        Currency base;
        uint64 unit;
        Currency quote;
        FeePolicy makerPolicy;
        IHooks hooks;
        FeePolicy takerPolicy;
        assembly {
            let d1 := mload(add(data, 0x20))
            base := d1
            unit := shr(160, d1)
            let d2 := mload(add(data, 0x40))
            quote := d2
            makerPolicy := shr(160, d2)
            let d3 := mload(add(data, 0x60))
            hooks := d3
            takerPolicy := shr(160, d3)
        }

        return IBookManager.BookKey({
            base: base,
            unit: unit,
            quote: quote,
            makerPolicy: makerPolicy,
            hooks: hooks,
            takerPolicy: takerPolicy
        });
    }

    function isWhitelisted(address provider) external view returns (bool) {
        return uint256(bookManager.load(keccak256(abi.encode(provider, bytes32(uint256(16)))))) == 1;
    }

    function tokenOwed(address provider, Currency currency) external view returns (uint256) {
        return uint256(
            bookManager.load(keccak256(abi.encode(currency, keccak256(abi.encode(provider, bytes32(uint256(17)))))))
        );
    }

    function getLock(uint256 i) external view returns (address locker, address lockCaller) {
        unchecked {
            // not in assembly because OFFSET is in the library scope
            uint256 position = Lockers.LOCKERS_SLOT + (i * Lockers.LOCKER_STRUCT_SIZE);
            locker = address(uint160(uint256(bookManager.load(bytes32(position)))));
            lockCaller = address(uint160(uint256(bookManager.load(bytes32(position + 1)))));
        }
    }

    function getLockData() external view returns (uint128 length, uint128 nonzeroDeltaCount) {
        bytes32 data = bookManager.load(bytes32(Lockers.LOCK_DATA_SLOT));
        assembly {
            length := sub(data, 1)
            nonzeroDeltaCount := shr(128, data)
        }
    }

    function getLiquidity(BookId id, Tick from, uint256 n) external view returns (Liquidity[] memory liquidity) {
        liquidity = new Liquidity[](n);
        uint24 tickValue = from.toUint24();
        for (uint256 i = 0; i < n; ++i) {
            tickValue = _minGreaterThan(id, tickValue);
            if (tickValue == 0) break;
            Tick tick = tickValue.toTick();
            liquidity[i] = Liquidity({tick: tick, depth: bookManager.getDepth(id, tick)});
        }
    }

    function getExpectedInput(IController.TakeOrderParams memory params) external view returns (uint256, uint256) {
        IBookManager.BookKey memory key = getBookKey(params.id);

        if (bookManager.isEmpty(params.id)) return (0, 0); // Todo consider revert

        uint256 spendBaseAmount;
        uint256 takenQuoteAmount;

        Tick tick = bookManager.getLowest(params.id);

        while (params.quoteAmount > takenQuoteAmount) {
            unchecked {
                if (params.limitPrice < tick.toPrice()) break;
                uint256 maxAmount;
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = params.quoteAmount - takenQuoteAmount; // key.takerPolicy.calculateOriginalAmount(leftQuoteAmount, true);
                } else {
                    maxAmount = params.quoteAmount - takenQuoteAmount;
                }
                maxAmount = maxAmount.divide(key.unit, true);
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
                tick = _minGreaterThan(params.id, tick.toUint24()).toTick();
            }
        }
        return (takenQuoteAmount, spendBaseAmount);
    }

    function getExpectedOutput(IController.SpendOrderParams memory params) external view returns (uint256, uint256) {
        IBookManager.BookKey memory key = getBookKey(params.id);

        if (bookManager.isEmpty(params.id)) return (0, 0); // Todo consider revert

        uint256 leftBaseAmount = params.baseAmount;
        uint256 takenQuoteAmount;

        Tick tick = bookManager.getLowest(params.id);

        while (leftBaseAmount > 0) {
            unchecked {
                if (params.limitPrice < tick.toPrice()) break;
                uint256 maxAmount;
                if (key.takerPolicy.usesQuote()) {
                    maxAmount = leftBaseAmount;
                } else {
                    maxAmount = leftBaseAmount; //key.takerPolicy.calculateOriginalAmount(leftBaseAmount, false);
                }
                maxAmount = tick.baseToQuote(maxAmount, false) / key.unit;

                maxAmount = maxAmount.divide(key.unit, true);
                uint256 currentDepth = bookManager.getDepth(params.id, tick);

                uint256 quoteAmount = (currentDepth > maxAmount ? maxAmount : currentDepth) * key.unit;
                uint256 baseAmount = tick.quoteToBase(quoteAmount, true);

                if (key.takerPolicy.usesQuote()) {
                    quoteAmount = uint256(int256(quoteAmount) - key.takerPolicy.calculateFee(quoteAmount, false));
                } else {
                    baseAmount = uint256(baseAmount.toInt256() + key.takerPolicy.calculateFee(baseAmount, false));
                }

                if (baseAmount == 0) break;

                leftBaseAmount -= baseAmount;
                takenQuoteAmount += quoteAmount;
                tick = _minGreaterThan(params.id, tick.toUint24()).toTick();
            }
        }
        return (takenQuoteAmount, params.baseAmount - leftBaseAmount);
    }

    function _minGreaterThan(BookId id, uint24 from) internal view returns (uint24) {
        uint256 b0b1;
        uint256 b2;
        assembly {
            b0b1 := shr(8, from)
            b2 := and(from, 0xff)
        }
        uint256 b2Bitmap = (TickBitmap.MAX_UINT_256_MINUS_1 << b2) & _loadBitmap(id, b0b1);
        if (b2Bitmap == 0) {
            uint256 b0 = b0b1 >> 8;
            uint256 b1Bitmap = (TickBitmap.MAX_UINT_256_MINUS_1 << (b0b1 & 0xff)) & _loadBitmap(id, ~b0);
            if (b1Bitmap == 0) {
                uint256 b0Bitmap = (TickBitmap.MAX_UINT_256_MINUS_1 << b0) & _loadBitmap(id, TickBitmap.B0_BITMAP_KEY);
                if (b0Bitmap == 0) return 0;
                b0 = b0Bitmap.leastSignificantBit();
                b1Bitmap = _loadBitmap(id, ~b0);
            }
            b0b1 = (b0 << 8) | b1Bitmap.leastSignificantBit();
            b2Bitmap = _loadBitmap(id, b0b1);
        }
        b2 = b2Bitmap.leastSignificantBit();
        return uint24((b0b1 << 8) | b2);
    }

    function _loadBitmap(BookId id, uint256 key) internal view returns (uint256) {
        unchecked {
            bytes32 slot = keccak256(abi.encode(id, bytes32(uint256(15))));
            slot = keccak256(abi.encode(key, bytes32(uint256(slot) + 4)));
            return uint256(bookManager.load(slot));
        }
    }

    function _loadString(bytes32 slot) internal view returns (string memory str) {
        uint256 data = uint256(bookManager.load(slot));
        if (data & 1 == 0) {
            // @dev length < 32
            uint256 strLength;
            assembly {
                strLength := shr(1, and(data, 0xff))
                data := and(0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00, data)
            }
            str = string(abi.encode(data));
            assembly {
                mstore(str, strLength)
            }
        } else {
            uint256 strLength;
            uint256 nSlot;
            assembly {
                strLength := shr(1, sub(data, 1))
                nSlot := add(div(sub(data, 2), 64), 1)
            }

            str = string(bookManager.load(keccak256(abi.encode(slot)), nSlot));
            assembly {
                mstore(str, strLength)
            }
        }
    }
}
