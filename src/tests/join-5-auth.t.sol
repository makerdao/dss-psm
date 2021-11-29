// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.6.12;

import "ds-test/test.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";

import {Vat} from "dss/vat.sol";

import "../join-5-auth.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract TestToken is DSToken {

    constructor(string memory symbol_, uint8 decimals_) public DSToken(symbol_) {
        decimals = decimals_;
    }

}

contract User {

    AuthGemJoin5 public authGemJoin;
    DSToken     public xmpl;

    constructor(AuthGemJoin5 gemJoin_) public {
        authGemJoin = gemJoin_;
        xmpl = DSToken(address(authGemJoin.gem()));
    }

    function approveGems(address who, uint256 wad) public {
        xmpl.approve(who, wad);
    }

    function joinGem(uint256 wad) public {
        xmpl.approve(address(authGemJoin), wad);
        authGemJoin.join(address(this), wad, address(this));
    }

    function exitGem(uint256 wad) public {
        xmpl.approve(address(authGemJoin), wad);
        authGemJoin.exit(address(this), wad);
    }

}

contract AuthGemJoin5Test is DSTest {
    
    Hevm hevm;

    address me;

    Vat          vat;
    DSToken      xmpl;
    AuthGemJoin5 authGemJoin;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    bytes32 constant ilk = "xmpl";
    uint256 constant XMPL_WAD = 10 ** 6;
    
    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        vat = new Vat();

        xmpl = new TestToken("XMPL", 6);
        xmpl.mint(1000 ether);

        vat.init(ilk);

        authGemJoin = new AuthGemJoin5(address(vat), ilk, address(xmpl));
        vat.rely(address(authGemJoin));
        xmpl.approve(address(authGemJoin), uint256(-1));
    }

    function testFail_tooManyDecimals() public {
        TestToken xmpl19 = new TestToken("XMPL", 19);
        new AuthGemJoin5(address(vat), ilk, address(xmpl19));
    }

    function test_join() public {
        assertEq(xmpl.balanceOf(address(authGemJoin)), 0);
        assertEq(vat.gem(ilk, me), 0);

        authGemJoin.join(me, 1 * XMPL_WAD, me);

        assertEq(xmpl.balanceOf(address(authGemJoin)), 1 * XMPL_WAD);
        assertEq(vat.gem(ilk, me), 1 ether);
    }
    
    function testFail_joinNotAuthorized() public {
        User user = new User(authGemJoin);
        xmpl.transfer(address(user), 1 * XMPL_WAD);
        user.approveGems(address(authGemJoin), 1 * XMPL_WAD);
        
        user.joinGem(1 * XMPL_WAD);
    }
    
    function test_exit() public {
        authGemJoin.join(me, 1 * XMPL_WAD, me);

        assertEq(xmpl.balanceOf(address(authGemJoin)), 1 * XMPL_WAD);
        assertEq(vat.gem(ilk, me), 1 ether);

        authGemJoin.exit(me, 1 * XMPL_WAD);

        assertEq(xmpl.balanceOf(address(authGemJoin)), 0);
        assertEq(vat.gem(ilk, me), 0);
    }
    
    function testFail_exitAllowedWithBalance() public {
        User user = new User(authGemJoin);
        user.exitGem(1 * XMPL_WAD);
    }
    
    function test_exitAllowedWithBalance() public {
        User user = new User(authGemJoin);
        xmpl.transfer(address(user), 1 * XMPL_WAD);
        user.approveGems(address(authGemJoin), 1 * XMPL_WAD);
        authGemJoin.join(address(user), 1 * XMPL_WAD, address(user));

        assertEq(xmpl.balanceOf(address(authGemJoin)), 1 * XMPL_WAD);
        assertEq(vat.gem(ilk, address(user)), 1 ether);
        assertEq(xmpl.balanceOf(address(user)), 0);

        user.exitGem(1 * XMPL_WAD);

        assertEq(xmpl.balanceOf(address(authGemJoin)), 0);
        assertEq(vat.gem(ilk, address(user)), 0);
        assertEq(xmpl.balanceOf(address(user)), 1 * XMPL_WAD);
    }
}