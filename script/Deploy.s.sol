// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {BookManager} from "../src/BookManager.sol";

contract DeployScript is Script {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address internal constant BASE_OWNER_SAFE =
        0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d;
    address internal constant BASE_TREASURY =
        0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d;

    uint256 internal constant ARBITRUM_CHAIN_ID = 42161;
    address internal constant ARBITRUM_OWNER_SAFE =
        0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d;
    address internal constant ARBITRUM_TREASURY =
        0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d;

    uint256 internal constant MONAD_MAINNET_CHAIN_ID = 143;
    address internal constant MONAD_MAINNET_OWNER_SAFE =
        0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d;
    address internal constant MONAD_MAINNET_TREASURY =
        0xfb976Bae0b3Ef71843F1c6c63da7Df2e44B3836d;

    function run() public {
        // Deploy with the configured EOA private key.
        address deployer = msg.sender;

        uint256 chainId = block.chainid;

        (address owner, address defaultProvider) = _resolveOwners(
            chainId,
            deployer
        );

        vm.startBroadcast();

        string memory baseURI = string.concat(
            "https://clober.io/api/nft/chains/",
            Strings.toString(chainId),
            "/orders/"
        );
        string memory contractURI = string.concat(
            "https://clober.io/api/contract/chains/",
            Strings.toString(chainId)
        );

        // Constructor args match `deploy/BookManager.ts`.
        BookManager bookManager = new BookManager(
            owner,
            defaultProvider,
            baseURI,
            contractURI,
            "Clober Orderbook Maker Order",
            "CLOB-ORDER"
        );

        vm.stopBroadcast();

        console.log("BookManager deployed to:", address(bookManager));
    }

    function _resolveOwners(
        uint256 chainId,
        address
    ) internal pure returns (address owner, address defaultProvider) {
        // Matches the intent of `deploy/BookManager.ts`.
        if (chainId == BASE_CHAIN_ID) {
            owner = BASE_OWNER_SAFE;
            defaultProvider = BASE_TREASURY;
        } else if (chainId == MONAD_MAINNET_CHAIN_ID) {
            owner = MONAD_MAINNET_OWNER_SAFE;
            defaultProvider = MONAD_MAINNET_TREASURY;
        } else if (chainId == ARBITRUM_CHAIN_ID) {
            owner = ARBITRUM_OWNER_SAFE;
            defaultProvider = ARBITRUM_TREASURY;
        } else {
            revert("Unsupported chain");
        }
    }
}
