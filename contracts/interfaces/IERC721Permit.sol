// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IERC721Permit
 * @notice An interface for the ERC721 permit extension
 */
interface IERC721Permit is IERC721 {
    error InvalidSignature();
    error PermitExpired();

    /**
     * @notice The EIP-712 typehash for the permit struct used by the contract
     */
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    /**
     * @notice The EIP-712 domain separator for this contract
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Approve the spender to transfer the given tokenId
     * @param spender The address to approve
     * @param tokenId The tokenId to approve
     * @param deadline The deadline for the signature
     * @param v The recovery id of the signature
     * @param r The r value of the signature
     * @param s The s value of the signature
     */
    function permit(address spender, uint256 tokenId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice Get the current nonce for a token
     * @param tokenId The tokenId to get the nonce for
     * @return The current nonce
     */
    function nonces(uint256 tokenId) external view returns (uint256);
}
