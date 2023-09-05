// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {IERC721Permit} from "../interfaces/IERC721Permit.sol";

abstract contract ERC721Permit is ERC721, IERC721Permit, EIP712 {
    // keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    bytes32 public constant override PERMIT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;

    constructor(string memory name_, string memory symbol_, string memory version_)
        ERC721(name_, symbol_)
        EIP712(name_, version_)
    {}

    function permit(address spender, uint256 tokenId, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable
        override
    {
        if (block.timestamp > deadline) revert PermitExpired();

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, _getAndIncrementNonce(tokenId), deadline))
        );

        address owner = ownerOf(tokenId);
        if (spender == owner) revert InvalidSignature();

        if (Address.isContract(owner)) {
            if (IERC1271(owner).isValidSignature(digest, abi.encodePacked(r, s, v)) != 0x1626ba7e) {
                revert InvalidSignature();
            }
        } else {
            if (ECDSA.recover(digest, v, r, s) != owner) revert InvalidSignature();
        }

        _approve(spender, tokenId);
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC721Permit).interfaceId || super.supportsInterface(interfaceId);
    }

    function _getAndIncrementNonce(uint256 tokenId) internal virtual returns (uint256);
}
