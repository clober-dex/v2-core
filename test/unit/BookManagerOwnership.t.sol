// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "../../src/BookManager.sol";
import "../routers/MakeRouter.sol";
import "../routers/TakeRouter.sol";

contract BookManagerOwnershipTest is Test {
    address public constant DEFAULT_PROVIDER = address(0x1312);

    BookManager public bookManager;

    function setUp() public {
        bookManager = new BookManager(address(this), DEFAULT_PROVIDER, "URI", "URI", "name", "SYMBOL");
    }

    function testWhitelist() public {
        assertFalse(bookManager.isWhitelisted(address(0x1234)));

        vm.expectEmit(address(bookManager));
        emit IBookManager.Whitelist(address(0x1234));
        bookManager.whitelist(address(0x1234));

        assertTrue(bookManager.isWhitelisted(address(0x1234)));
    }

    function testWhitelistOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1111)));
        vm.prank(address(0x1111));
        bookManager.whitelist(address(0x1234));
    }

    function testDelist() public {
        bookManager.whitelist(address(0x1234));

        assertTrue(bookManager.isWhitelisted(address(0x1234)));

        vm.expectEmit(address(bookManager));
        emit IBookManager.Delist(address(0x1234));
        bookManager.delist(address(0x1234));

        assertFalse(bookManager.isWhitelisted(address(0x1234)));
    }

    function testDelistOwnership() public {
        bookManager.whitelist(address(0x1234));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1111)));
        vm.prank(address(0x1111));
        bookManager.delist(address(0x1234));
    }

    function testSetDefaultProvider() public {
        assertEq(bookManager.defaultProvider(), DEFAULT_PROVIDER);

        vm.expectEmit(address(bookManager));
        emit IBookManager.SetDefaultProvider(address(0x1234));
        bookManager.setDefaultProvider(address(0x1234));

        assertEq(bookManager.defaultProvider(), address(0x1234));
    }

    function testSetDefaultProviderOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1111)));
        vm.prank(address(0x1111));
        bookManager.setDefaultProvider(address(0x1234));
    }
}
