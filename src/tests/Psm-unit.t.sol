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

import {DaiJoinMock} from "./mocks/DaiJoinMock.sol";
import {DaiMock} from "./mocks/DaiMock.sol";
import {SpotterMock} from "./mocks/SpotterMock.sol";
import {TokenMock} from "./mocks/TokenMock.sol";
import {VatMock} from "./mocks/VatMock.sol";
import {Psm} from "../Psm.sol";

contract User {

    Psm public psm;

    constructor(Psm psm_) {
        psm = psm_;

        psm.gem().approve(address(psm), type(uint256).max);
        psm.dai().approve(address(psm), type(uint256).max);
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

contract PsmUnitTest is DSSTest {

    VatMock vat;
    DaiJoinMock daiJoin;
    DaiMock dai;
    SpotterMock spotter;
    address vow;

    DSValue pip;
    TokenMock gem;

    Psm psm;

    bytes32 constant ILK = "PSM-USDX-A";

    int256 constant TOLL_ONE_PCT = 10 ** 16;
    uint256 constant ONE_USDX = 10 ** 6;

    event File(bytes32 indexed what, int256 data);
    event SellGem(address indexed owner, uint256 gemsLocked, uint256 daiMinted, int256 fee);
    event BuyGem(address indexed owner, uint256 gemsUnlocked, uint256 daiBurned, int256 fee);
    event Exit(address indexed usr, uint256 amt);

    function postSetup() internal virtual override {
        vat = new VatMock();
        dai = new DaiMock();
        spotter = new SpotterMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        vow = address(123);
        pip = new DSValue();
        pip.poke(bytes32(WAD));    // $1
        spotter.setPip(ILK, address(pip));
        gem = new TokenMock();
        gem.mint(address(this), 1000 * ONE_USDX);

        psm = new Psm(ILK, address(gem), address(daiJoin), address(spotter));
        psm.file("vow", vow);

        vat.file("Line", 1000 * RAD);
    }

    function testConstructor() public {
        assertEq(psm.ilk(), ILK);
        assertEq(address(psm.gem()), address(gem));
        assertEq(address(psm.vat()), address(vat));
        assertEq(address(psm.dai()), address(dai));
        assertEq(address(psm.daiJoin()), address(daiJoin));

        assertEq(psm.wards(address(this)), 1);
        assertEq(vat.can(address(psm), address(daiJoin)), 1);
        assertEq(dai.allowance(address(psm), address(daiJoin)), type(uint256).max);
    }

    function testRelyDeny() public {
        checkAuth(address(psm), "Psm");
    }

    function testFileVow() public {
        checkFileAddress(address(psm), "Psm", ["vow"]);
    }

    function testFileTolls() public {
        assertEq(psm.tin(), 0);
        vm.expectEmit(true, false, false, true);
        emit File("tin", int256(123));
        psm.file("tin", 123);
        assertEq(psm.tin(), 123);

        assertEq(psm.tout(), 0);
        vm.expectEmit(true, false, false, true);
        emit File("tout", int256(123));
        psm.file("tout", 123);
        assertEq(psm.tout(), 123);

        int256 SWAD = int256(WAD);
        psm.file("tin", SWAD);
        assertEq(psm.tin(), SWAD);
        vm.expectRevert("Psm/out-of-range");
        psm.file("tin", SWAD + 1);
        psm.file("tin", -SWAD);
        assertEq(psm.tin(), -SWAD);
        vm.expectRevert("Psm/out-of-range");
        psm.file("tin", -SWAD - 1);

        psm.file("tout", SWAD);
        assertEq(psm.tout(), SWAD);
        vm.expectRevert("Psm/out-of-range");
        psm.file("tout", SWAD + 1);
        psm.file("tout", -SWAD);
        assertEq(psm.tout(), -SWAD);
        vm.expectRevert("Psm/out-of-range");
        psm.file("tout", -SWAD - 1);

        vm.expectRevert("Psm/file-unrecognized-param");
        psm.file("bad value", 123);
    }

    function testSellGemNoFee() public {
        assertEq(gem.balanceOf(address(this)), 1000 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(vat.dai(vow), 0);

        gem.approve(address(psm), type(uint256).max);
        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), 100 * ONE_USDX, 100 * WAD, 0);
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(vat.dai(vow), 0);
        (uint256 inkme, uint256 artme) = vat.urns(ILK, address(this));
        assertEq(inkme, 0);
        assertEq(artme, 0);
        (uint256 inkpsm, uint256 artpsm) = vat.urns(ILK, address(psm));
        assertEq(inkpsm, 100 ether);
        assertEq(artpsm, 100 ether);
    }

    function testSellGemFee() public {
        psm.file("tin", TOLL_ONE_PCT);

        assertEq(gem.balanceOf(address(this)), 1000 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(vat.dai(vow), 0);

        gem.approve(address(psm), type(uint256).max);
        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), 100 * ONE_USDX, 99 * WAD, int256(WAD));
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 99 ether);
        assertEq(vat.dai(vow), RAD);
    }

    function testSellGemNegativeFee() public {
        psm.file("tin", -TOLL_ONE_PCT);     // Pay the user 1%

        assertEq(gem.balanceOf(address(this)), 1000 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(vat.dai(vow), 0);
        assertEq(vat.sin(vow), 0);

        gem.approve(address(psm), type(uint256).max);
        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), 100 * ONE_USDX, 101 * WAD, -int256(WAD));
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 101 ether);
        assertEq(vat.dai(vow), 0);
        assertEq(vat.sin(vow), RAD);
    }

    function testSwapBothNoFee() public {
        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 100 * ONE_USDX);
        dai.approve(address(psm), 40 ether);
        vm.expectEmit(true, false, false, true);
        emit BuyGem(address(this), 40 * ONE_USDX, 40 * WAD, 0);
        psm.buyGem(address(this), 40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 940 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 60 ether);
        assertEq(vat.dai(vow), 0);
        (uint256 ink, uint256 art) = vat.urns(ILK, address(psm));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }

    function testSwapBothFees() public {
        psm.file("tin", 5 * TOLL_ONE_PCT);
        psm.file("tout", 10 * TOLL_ONE_PCT);

        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX);
        assertEq(dai.balanceOf(address(this)), 95 ether);
        assertEq(vat.dai(vow), 5 * RAD);
        (uint256 ink1, uint256 art1) = vat.urns(ILK, address(psm));
        assertEq(ink1, 100 ether);
        assertEq(art1, 100 ether);

        dai.approve(address(psm), 44 ether);
        vm.expectEmit(true, false, false, true);
        emit BuyGem(address(this), 40 * ONE_USDX, 44 * WAD, 4 * int256(WAD));
        psm.buyGem(address(this), 40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 940 * ONE_USDX);
        assertEq(dai.balanceOf(address(this)), 51 ether);
        assertEq(vat.dai(vow),  9 * RAD);
        (uint256 ink2, uint256 art2) = vat.urns(ILK, address(psm));
        assertEq(ink2, 60 ether);
        assertEq(art2, 60 ether);
    }

    function testSwapBothNegativeFees() public {
        psm.file("tin", -5 * TOLL_ONE_PCT);
        psm.file("tout", -10 * TOLL_ONE_PCT);
        gem.approve(address(psm), type(uint256).max);
        dai.approve(address(psm), type(uint256).max);

        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX);
        assertEq(dai.balanceOf(address(this)), 105 ether);
        assertEq(vat.dai(vow), 0);
        assertEq(vat.sin(vow), 5 * RAD);
        (uint256 ink1, uint256 art1) = vat.urns(ILK, address(psm));
        assertEq(ink1, 100 ether);
        assertEq(art1, 100 ether);

        vm.expectEmit(true, false, false, true);
        emit BuyGem(address(this), 40 * ONE_USDX, 36 * WAD, -4 * int256(WAD));
        psm.buyGem(address(this), 40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 940 * ONE_USDX);
        assertEq(dai.balanceOf(address(this)), 69 ether);
        assertEq(vat.dai(vow), 0);
        assertEq(vat.sin(vow), 9 * RAD);
        (uint256 ink2, uint256 art2) = vat.urns(ILK, address(psm));
        assertEq(ink2, 60 ether);
        assertEq(art2, 60 ether);
    }

    function testSwapBothOther() public {
        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX);
        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(vat.dai(vow), 0);

        User someUser = new User(psm);
        dai.mint(address(someUser), 45 ether);
        someUser.buyGem(40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX);
        assertEq(gem.balanceOf(address(someUser)), 40 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0 ether);
        assertEq(vat.gem(ILK, address(someUser)), 0 ether);
        assertEq(vat.dai(address(this)), 0);
        assertEq(vat.dai(address(someUser)), 0);
        assertEq(dai.balanceOf(address(this)), 100 ether);
        assertEq(dai.balanceOf(address(someUser)), 5 ether);
        assertEq(vat.dai(vow), 0);
        (uint256 ink, uint256 art) = vat.urns(ILK, address(psm));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }

    function testSwapBothOtherSmallFee() public {
        psm.file("tin", 1);

        User user1 = new User(psm);
        gem.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);

        assertEq(gem.balanceOf(address(user1)), 0 * ONE_USDX);
        assertEq(dai.balanceOf(address(user1)), 40 ether - 40);
        assertEq(vat.dai(vow), 40 * RAY);
        (uint256 ink1, uint256 art1) = vat.urns(ILK, address(psm));
        assertEq(ink1, 40 ether);
        assertEq(art1, 40 ether);

        user1.buyGem(40 * ONE_USDX - 1);

        assertEq(gem.balanceOf(address(user1)), 40 * ONE_USDX - 1);
        assertEq(dai.balanceOf(address(user1)), 999999999960);
        assertEq(vat.dai(vow), 40 * RAY);
        (uint256 ink2, uint256 art2) = vat.urns(ILK, address(psm));
        assertEq(ink2, 1 * 10 ** 12);
        assertEq(art2, 1 * 10 ** 12);
    }

    function testSellGemInsufficientGem() public {
        User user1 = new User(psm);
        vm.expectRevert("Gem/insufficient-balance");
        user1.sellGem(40 * ONE_USDX);
    }

    function testSwapBothSmallFeeInsufficientDai() public {
        psm.file("tin", 1);        // Very small fee pushes you over the edge

        User user1 = new User(psm);
        gem.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);
        vm.expectRevert("Dai/insufficient-balance");
        user1.buyGem(40 * ONE_USDX);
    }

    function testSellGemOverLine() public {
        gem.mint(address(this), 1000 * ONE_USDX);
        gem.approve(address(psm), type(uint256).max);
        vm.expectRevert("Vat/ceiling-exceeded");
        psm.sellGem(address(this), 2000 * ONE_USDX);
    }

    function testTwoUsersInsufficientDai() public {
        User user1 = new User(psm);
        gem.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);

        User user2 = new User(psm);
        dai.mint(address(user2), 39 ether);
        vm.expectRevert("Dai/insufficient-balance");
        user2.buyGem(40 * ONE_USDX);
    }

    function testSwapBothZero() public {
        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 0);
        dai.approve(address(psm), type(uint256).max);
        psm.buyGem(address(this), 0);
    }

    function testExit() public {
        // Add some gems to psm
        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 100 * ONE_USDX);

        // I got some gems somehow
        vat.slip(ILK, address(this), int256(50 ether));

        // Can exit at 1:1
        assertEq(vat.gem(ILK, address(this)), 50 ether);
        assertEq(gem.balanceOf(address(123)), 0);

        psm.exit(address(123), 50 * ONE_USDX);

        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(gem.balanceOf(address(123)), 50 * ONE_USDX);
    }

    function testExitMissingGems() public {
        vm.expectRevert("Vat/underflow");
        psm.exit(address(123), 50 * ONE_USDX);
    }
    
}
