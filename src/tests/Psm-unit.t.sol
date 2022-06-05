// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2022 Dai Foundation
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

pragma solidity ^0.8.14;

import "dss-test/DSSTest.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";

import {Psm} from "../Psm.sol";

contract TestToken is DSToken {

    constructor(string memory symbol_, uint8 decimals_) public DSToken(symbol_) {
        decimals = decimals_;
    }

}

contract User {

    Psm public psm;

    constructor(Psm psm_) public {
        psm = psm_;

        psm.gem().approve(address(psm), type(uint256).max);
        dai.approve(address(psm), type(uint256).max);
    }

    function sellGem(uint256 value) public {
        psm.sellGem(address(this), value);
    }

    function buyGem(uint256 value) public {
        psm.buyGem(address(this), value);
    }

    function exit(uint256 value) public {
        psm.exit(address(this), value);
    }

}

contract PsmTest is DSSTest {

    VatMock vat;
    DaiJoinMock daiJoin;
    DaiMock dai;
    address vow;

    DSValue pip;
    TestToken gem;

    Psm psm;

    bytes32 constant ILK = "PSM-USDX-A";

    uint256 constant TOLL_ONE_PCT = 10 ** 16;
    uint256 constant ONE_USDX = 10 ** 6;

    function postSetup() internal virtual override {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        vow = address(123);
        pip = new DSValue();
        gem = new TestToken("USDX", 6);
        gem.mint(1000 * ONE_USDX);

        psm = new Psm(ILK, address(gem), address(daiJoin));
        psm.file("vow", vow);

        vat.file(ilk, "line", 1000 * RAD);
        vat.file("Line",      1000 * RAD);
    }

    function testConstructor() public {
        assertEq(psm.ilk(), ILK);
        assertEq(address(psm.gem()), address(gem));
        assertEq(address(psm.vat()), address(vat));
        assertEq(address(psm.dai()), address(dai));
        assertEq(address(psm.daiJoin()), address(daiJoin));

        assertEq(vat.can(address(psm), address(daiJoin)), 1);
        assertEq(dai.allowance(address(psm), address(daiJoin)), type(uint256).max);
    }

    function testRelyDeny() public {
        checkAuth(address(psm), "Psm");
    }

    function testFile() public {
        checkFileAddress(address(psm), "Psm", ["vow"]);
    }

    function test_sellGem_no_fee() public {
        assertEq(usdx.balanceOf(me), 1000 * ONE_USDX);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 0);
        assertEq(vow.Joy(), 0);

        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * ONE_USDX);

        assertEq(usdx.balanceOf(me), 900 * ONE_USDX);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 100 ether);
        assertEq(vow.Joy(), 0);
        (uint256 inkme, uint256 artme) = vat.urns(ilk, me);
        assertEq(inkme, 0);
        assertEq(artme, 0);
        (uint256 inkpsm, uint256 artpsm) = vat.urns(ilk, address(psmA));
        assertEq(inkpsm, 100 ether);
        assertEq(artpsm, 100 ether);
    }

    function test_sellGem_fee() public {
        psmA.file("tin", TOLL_ONE_PCT);

        assertEq(usdx.balanceOf(me), 1000 * ONE_USDX);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 0);
        assertEq(vow.Joy(), 0);

        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * ONE_USDX);

        assertEq(usdx.balanceOf(me), 900 * ONE_USDX);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 99 ether);
        assertEq(vow.Joy(), rad(1 ether));
    }

    function test_swap_both_no_fee() public {
        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * ONE_USDX);
        dai.approve(address(psmA), 40 ether);
        psmA.buyGem(me, 40 * ONE_USDX);

        assertEq(usdx.balanceOf(me), 940 * ONE_USDX);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(vat.dai(me), 0);
        assertEq(dai.balanceOf(me), 60 ether);
        assertEq(vow.Joy(), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(psmA));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }

    function test_swap_both_fees() public {
        psmA.file("tin", 5 * TOLL_ONE_PCT);
        psmA.file("tout", 10 * TOLL_ONE_PCT);

        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * ONE_USDX);

        assertEq(usdx.balanceOf(me), 900 * ONE_USDX);
        assertEq(dai.balanceOf(me), 95 ether);
        assertEq(vow.Joy(), rad(5 ether));
        (uint256 ink1, uint256 art1) = vat.urns(ilk, address(psmA));
        assertEq(ink1, 100 ether);
        assertEq(art1, 100 ether);

        dai.approve(address(psmA), 44 ether);
        psmA.buyGem(me, 40 * ONE_USDX);

        assertEq(usdx.balanceOf(me), 940 * ONE_USDX);
        assertEq(dai.balanceOf(me), 51 ether);
        assertEq(vow.Joy(), rad(9 ether));
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(psmA));
        assertEq(ink2, 60 ether);
        assertEq(art2, 60 ether);
    }

    function test_swap_both_other() public {
        usdx.approve(address(gemA));
        psmA.sellGem(me, 100 * ONE_USDX);

        assertEq(usdx.balanceOf(me), 900 * ONE_USDX);
        assertEq(dai.balanceOf(me), 100 ether);
        assertEq(vow.Joy(), rad(0 ether));

        User someUser = new User(dai, gemA, psmA);
        dai.mint(address(someUser), 45 ether);
        someUser.buyGem(40 * ONE_USDX);

        assertEq(usdx.balanceOf(me), 900 * ONE_USDX);
        assertEq(usdx.balanceOf(address(someUser)), 40 * ONE_USDX);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.gem(ilk, address(someUser)), 0 ether);
        assertEq(vat.dai(me), 0);
        assertEq(vat.dai(address(someUser)), 0);
        assertEq(dai.balanceOf(me), 100 ether);
        assertEq(dai.balanceOf(address(someUser)), 5 ether);
        assertEq(vow.Joy(), rad(0 ether));
        (uint256 ink, uint256 art) = vat.urns(ilk, address(psmA));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }

    function test_swap_both_other_small_fee() public {
        psmA.file("tin", 1);

        User user1 = new User(dai, gemA, psmA);
        usdx.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);

        assertEq(usdx.balanceOf(address(user1)), 0 * ONE_USDX);
        assertEq(dai.balanceOf(address(user1)), 40 ether - 40);
        assertEq(vow.Joy(), rad(40));
        (uint256 ink1, uint256 art1) = vat.urns(ilk, address(psmA));
        assertEq(ink1, 40 ether);
        assertEq(art1, 40 ether);

        user1.buyGem(40 * ONE_USDX - 1);

        assertEq(usdx.balanceOf(address(user1)), 40 * ONE_USDX - 1);
        assertEq(dai.balanceOf(address(user1)), 999999999960);
        assertEq(vow.Joy(), rad(40));
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(psmA));
        assertEq(ink2, 1 * 10 ** 12);
        assertEq(art2, 1 * 10 ** 12);
    }

    function testFail_sellGem_insufficient_gem() public {
        User user1 = new User(dai, gemA, psmA);
        user1.sellGem(40 * ONE_USDX);
    }

    function testFail_swap_both_small_fee_insufficient_dai() public {
        psmA.file("tin", 1);        // Very small fee pushes you over the edge

        User user1 = new User(dai, gemA, psmA);
        usdx.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);
        user1.buyGem(40 * ONE_USDX);
    }

    function testFail_sellGem_over_line() public {
        usdx.mint(1000 * ONE_USDX);
        usdx.approve(address(gemA));
        psmA.buyGem(me, 2000 * ONE_USDX);
    }

    function testFail_two_users_insufficient_dai() public {
        User user1 = new User(dai, gemA, psmA);
        usdx.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);

        User user2 = new User(dai, gemA, psmA);
        dai.mint(address(user2), 39 ether);
        user2.buyGem(40 * ONE_USDX);
    }

    function test_swap_both_zero() public {
        usdx.approve(address(gemA), uint(-1));
        psmA.sellGem(me, 0);
        dai.approve(address(psmA), uint(-1));
        psmA.buyGem(me, 0);
    }

    function testFail_direct_deposit() public {
        usdx.approve(address(gemA), uint(-1));
        gemA.join(me, 10 * ONE_USDX, me);
    }
    
}
