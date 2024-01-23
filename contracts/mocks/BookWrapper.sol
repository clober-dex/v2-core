// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@clober/library/contracts/SegmentedSegmentTree.sol";

import "../libraries/ERC721Permit.sol";

contract TestWrapper is Ownable2Step, ERC721Permit {
    using SegmentedSegmentTree for SegmentedSegmentTree.Core;

    SegmentedSegmentTree.Core internal tree;

    constructor(address owner_, string memory name_, string memory symbol_)
        Ownable(owner_)
        ERC721Permit(name_, symbol_, "2")
    {}

    function get(uint256 index) external view returns (uint64 ret) {
        return tree.get(index);
    }

    function total() external view returns (uint64) {
        return tree.total();
    }

    function query(uint256 left, uint256 right) external view returns (uint64 sum) {
        return tree.query(left, right);
    }

    function update(uint256 index, uint64 value) external returns (uint64 replaced) {
        return tree.update(index, value);
    }

    function _ownerOf(uint256 tokenId) internal view override returns (address) {
        return address(0);
    }

    function _setOwner(uint256 tokenId, address owner) internal override {}

    function _getAndIncrementNonce(uint256 id) internal override returns (uint256 nonce) {
        return 0;
    }

    function nonces(uint256 tokenId) external view returns (uint256) {
        return 0;
    }
}
