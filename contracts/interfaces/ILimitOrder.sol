// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

import "../libraries/CurrencyLibrary.sol";
import "./IBookManager.sol";

interface ILimitOrder is IERC721, IERC721Metadata {
    function bookKey(uint256 id) external view returns (IBookManager.BookKey calldata);

    function maker(uint256 id) external view returns (address);

    function provider(uint256 id) external view returns (address);

    function priceIndex(uint256 id) external view returns (uint24);

    function price(uint256 id) external view returns (uint256);

    /// @notice Returns information about the limit order's size
    /// @param id The NFT id of the limit order
    /// @return initial The initial size of the limit order
    /// @return reduced The sum of reductions done to the limit order
    /// @return filled The total amount taken from the limit order
    /// @return claimable The currently available claimable amount from the limit order getting filled
    function amount(uint256 id)
        external
        returns (
            uint64 initial,
            uint64 reduced,
            uint64 filled,
            uint64 claimable
        );

    function reduce(uint256 id, uint64 amount) external;

    function cancel(uint256 id) external;

    function fill(uint256 id, uint64 amount) external;

    function claim(uint256 id) external;
}
