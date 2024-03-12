// SPDX-FileCopyrightText: © 2023 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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
pragma solidity ^0.8.16;

import "dss-test/DssTest.sol";
import {DaiJoinMock} from "./mocks/DaiJoinMock.sol";
import {DaiMock} from "./mocks/DaiMock.sol";
import {TokenMock} from "./mocks/TokenMock.sol";
import {YieldBearingTokenMock} from "./mocks/YieldBearingTokenMock.sol";
import {VatMock} from "./mocks/VatMock.sol";
import {DssYieldBearingPsm} from "./DssYieldBearingPsm.sol";

contract User {
    DssYieldBearingPsm public psm;

    constructor(DssYieldBearingPsm psm_) {
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
}

contract DssYieldBearingPsmTest is DssTest {
    VatMock vat;
    DaiJoinMock daiJoin;
    DaiMock dai;
    address vow;

    TokenMock asset;
    YieldBearingTokenMock gem;
    DssYieldBearingPsm psm;

    bytes32 constant ILK = "PSM-SUSDX-A";
    int256 constant TOLL_ONE_PCT = 10 ** 16;
    uint256 constant ONE_USDX = 10 ** 18;

    function setUp() public {
        vat = new VatMock();
        dai = new DaiMock();
        daiJoin = new DaiJoinMock(address(vat), address(dai));
        vow = address(123);
        asset = new TokenMock("USDX", "USDX");
        asset.mint(address(this), 1250 * ONE_USDX);
        gem = new YieldBearingTokenMock(address(asset), "sUSDX", "sUSDX");
        asset.approve(address(gem), type(uint256).max);
        gem.deposit(1250 * ONE_USDX, address(this));

        // Burning 250 gem so the "price" of it becomes larger than the underlying asset
        gem.burn(address(this), 250 * ONE_USDX);

        psm = new DssYieldBearingPsm(ILK, address(gem), address(daiJoin));
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
        checkAuth(address(psm), "DssYieldBearingPsm");
    }

    function testFileVow() public {
        checkFileAddress(address(psm), "DssYieldBearingPsm", ["vow"]);
    }

    function testFileTolls() public {
        assertEq(psm.tin(), 0);
        vm.expectEmit(true, false, false, true);
        emit File("tin", int256(123));
        psm.file("tin", int256(123));
        assertEq(psm.tin(), 123);

        vm.expectEmit(true, false, false, true);
        emit File("tin", psm.SHALTED());
        psm.file("tin", psm.SHALTED());
        assertEq(psm.tin(), psm.SHALTED());

        assertEq(psm.tout(), 0);
        vm.expectEmit(true, false, false, true);
        emit File("tout", int256(123));
        psm.file("tout", int256(123));
        assertEq(psm.tout(), 123);

        vm.expectEmit(true, false, false, true);
        emit File("tout", psm.SHALTED());
        psm.file("tout", psm.SHALTED());
        assertEq(psm.tout(), psm.SHALTED());

        int256 SWAD = int256(WAD);
        psm.file("tin", SWAD);
        assertEq(psm.tin(), SWAD);
        vm.expectRevert("DssYieldBearingPsm/tin-out-of-range");
        psm.file("tin", SWAD + 1);
        psm.file("tin", -SWAD);
        assertEq(psm.tin(), -SWAD);
        vm.expectRevert("DssYieldBearingPsm/tin-out-of-range");
        psm.file("tin", -SWAD - 1);

        psm.file("tout", SWAD);
        assertEq(psm.tout(), SWAD);
        vm.expectRevert("DssYieldBearingPsm/tout-out-of-range");
        psm.file("tout", SWAD + 1);
        psm.file("tout", -SWAD);
        assertEq(psm.tout(), -SWAD);
        vm.expectRevert("DssYieldBearingPsm/tout-out-of-range");
        psm.file("tout", -SWAD - 1);

        vm.expectRevert("DssYieldBearingPsm/file-unrecognized-param");
        psm.file("bad value", int256(123));

        vm.expectRevert("DssYieldBearingPsm/file-unrecognized-param");
        psm.file("bad value", uint256(123));

        // Reverts when trying to use the compatibility overload to set regular values
        vm.expectRevert("DssYieldBearingPsm/tout-out-of-range");
        psm.file("tout", uint256(123));
        vm.expectRevert("DssYieldBearingPsm/tin-out-of-range");
        psm.file("tin", uint256(123));
    }

    function testSellGemNoFee() public {
        assertEq(gem.balanceOf(address(this)), 1000 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(vat.dai(vow), 0);

        gem.approve(address(psm), type(uint256).max);
        vm.expectEmit(true, false, false, true);
        emit SellGem(address(this), 100 * ONE_USDX, 0, gem.convertToAssets(100 * WAD));
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX, "Gem: invalid balance");
        assertEq(vat.gem(ILK, address(this)), 0, "Vat gem: invalid value");
        assertEq(vat.dai(address(this)), 0, "Vat dai: invalid value this");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(100 * WAD), "Dai: invalid balance");
        assertEq(vat.dai(vow), 0, "Vat dai: invalid value vow");
        (uint256 inkme, uint256 artme) = vat.urns(ILK, address(this));
        assertEq(inkme, 0, "Vat ink: invalid value this");
        assertEq(artme, 0, "Vat art: invalid value this");
        (uint256 inkpsm, uint256 artpsm) = vat.urns(ILK, address(psm));
        assertEq(inkpsm, gem.convertToAssets(100 * WAD), "Vat ink: invalid value psm");
        assertEq(artpsm, gem.convertToAssets(100 * WAD), "Vat art: invalid value psm");
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
        uint256 fee = gem.convertToAssets(1 * WAD);
        emit SellGem(address(this), 100 * ONE_USDX, int256(fee), gem.convertToAssets(100 * WAD) - fee);
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX, "Gem: invalid balance");
        assertEq(vat.gem(ILK, address(this)), 0, "Vat gem: invalid value");
        assertEq(vat.dai(address(this)), 0, "Vat dai: invalid value this");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(99 * WAD), "Dai: invalid balance");
        assertEq(vat.dai(vow), gem.convertToAssets(1 * RAD), "Dai: invalid value vow");
    }

    function testSellGemNegativeFee() public {
        psm.file("tin", -TOLL_ONE_PCT); // Pay the user 1%

        assertEq(gem.balanceOf(address(this)), 1000 * ONE_USDX);
        assertEq(vat.gem(ILK, address(this)), 0);
        assertEq(vat.dai(address(this)), 0);
        assertEq(dai.balanceOf(address(this)), 0);
        assertEq(vat.dai(vow), 0);
        assertEq(vat.sin(vow), 0);

        gem.approve(address(psm), type(uint256).max);
        vm.expectEmit(true, false, false, true);
        uint256 subsidy = gem.convertToAssets(1 * WAD);
        emit SellGem(address(this), 100 * ONE_USDX, -int256(subsidy), gem.convertToAssets(100 * WAD) + subsidy);
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX, "Gem: invalid balance");
        assertEq(vat.gem(ILK, address(this)), 0, "Vat gem: invalid value");
        assertEq(vat.dai(address(this)), 0, "Vat dai: invalid value this");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(101 * WAD), "Dai: invalid balance");
        assertEq(vat.dai(vow), 0, "Vat dai: invalid value vow");
        assertEq(vat.sin(vow), gem.convertToAssets(RAD), "Dai: invalid value sin");
    }

    function testSwapBothNoFee() public {
        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 100 * ONE_USDX);
        dai.approve(address(psm), gem.convertToAssets(40 * WAD));
        vm.expectEmit(true, false, false, true);
        emit BuyGem(address(this), 40 * ONE_USDX, 0, gem.convertToAssets(40 * WAD));
        psm.buyGem(address(this), 40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 940 * ONE_USDX, "Gem: invalid balance");
        assertEq(vat.gem(ILK, address(this)), 0, "Vat gem: invalid value");
        assertEq(vat.dai(address(this)), 0, "Vat dai: invalid value this");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(60 * WAD), "Dai: invalid balance");
        assertEq(vat.dai(vow), 0, "Vat dai: invalid value vow");
        (uint256 ink, uint256 art) = vat.urns(ILK, address(psm));
        assertEq(ink, gem.convertToAssets(60 * WAD), "Vat ink: invalid value psm");
        assertEq(art, gem.convertToAssets(60 * WAD), "Vat art: invalid value psm");
    }

    function testSwapBothFees() public {
        psm.file("tin", 5 * TOLL_ONE_PCT);
        psm.file("tout", 10 * TOLL_ONE_PCT);

        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX, "(sell) Gem: invalid balance");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(95 * WAD), "(sell) Dai: invalid balance");
        assertEq(vat.dai(vow), gem.convertToAssets(5 * RAD), "(sell): Vat dai: invalid value vow");
        (uint256 ink1, uint256 art1) = vat.urns(ILK, address(psm));
        assertEq(ink1, gem.convertToAssets(100 * WAD), "(sell) Vat ink: invalid value psm");
        assertEq(art1, gem.convertToAssets(100 * WAD), "(sell) Vat art: invalid value psm");

        dai.approve(address(psm), gem.convertToAssets(44 * WAD));
        vm.expectEmit(true, false, false, true);
        uint256 fee = gem.convertToAssets(4 * WAD);
        emit BuyGem(address(this), 40 * ONE_USDX, int256(fee), gem.convertToAssets(40 * WAD) + fee);
        psm.buyGem(address(this), 40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 940 * ONE_USDX, "(buy) Gem: invalid balance");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(51 * WAD), "(buy) Dai: invalid balance");
        assertEq(vat.dai(vow), gem.convertToAssets(9 * RAD), "(buy): Vat dai: invalid value vow");
        (uint256 ink2, uint256 art2) = vat.urns(ILK, address(psm));
        assertEq(ink2, gem.convertToAssets(60 * WAD), "(buy) Vat ink: invalid value psm");
        assertEq(art2, gem.convertToAssets(60 * WAD), "(buy) Vat art: invalid value psm");
    }

    function testSwapBothNegativeFees() public {
        psm.file("tin", -5 * TOLL_ONE_PCT);
        psm.file("tout", -10 * TOLL_ONE_PCT);
        gem.approve(address(psm), type(uint256).max);
        dai.approve(address(psm), type(uint256).max);

        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX, "(sell) Gem: invalid balance");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(105 * WAD), "(sell) Dai: invalid balance");
        assertEq(vat.dai(vow), 0, "(sell): Vat dai: invalid value vow");
        assertEq(vat.sin(vow), gem.convertToAssets(5 * RAD), "(sell): Vat dai: invalid value sin");
        (uint256 ink1, uint256 art1) = vat.urns(ILK, address(psm));
        assertEq(ink1, gem.convertToAssets(100 * WAD), "(sell) Vat ink: invalid value psm");
        assertEq(art1, gem.convertToAssets(100 * WAD), "(sell) Vat art: invalid value psm");

        vm.expectEmit(true, false, false, true);
        uint256 subsidy = gem.convertToAssets(4 * WAD);
        emit BuyGem(address(this), 40 * ONE_USDX, -int256(subsidy), gem.convertToAssets(40 * WAD) - subsidy);
        psm.buyGem(address(this), 40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 940 * ONE_USDX, "(buy) Gem: invalid balance");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(69 * WAD), "(buy) Dai: invalid balance");
        assertEq(vat.dai(vow), 0, "(buy) Vat dai: invalid value vow");
        assertEq(vat.sin(vow), gem.convertToAssets(9 * RAD), "(buy) Vat dai: invalid value sin");
        (uint256 ink2, uint256 art2) = vat.urns(ILK, address(psm));
        assertEq(ink2, gem.convertToAssets(60 * WAD), "(buy) Vat ink: invalid value psm");
        assertEq(art2, gem.convertToAssets(60 * WAD), "(buy) Vat art: invalid value psm");
    }

    function testSwapBothOther() public {
        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 100 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX, "(sell) Gem: invalid balance");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(100 * WAD), "(sell) Dai: invalid balance");
        assertEq(vat.dai(vow), 0, "(sell) Vat dai: invalid value vow");

        User someUser = new User(psm);
        dai.mint(address(someUser), gem.convertToAssets(45 * WAD));
        someUser.buyGem(40 * ONE_USDX);

        assertEq(gem.balanceOf(address(this)), 900 * ONE_USDX, "(buy) Gem: invalid balance this");
        assertEq(gem.balanceOf(address(someUser)), 40 * ONE_USDX, "(buy) Gem: invalid balance user");
        assertEq(vat.gem(ILK, address(this)), 0, "(buy) Vat gem: invalid value this");
        assertEq(vat.gem(ILK, address(someUser)), 0, "(buy) Vat gem: invalid value user");
        assertEq(vat.dai(address(this)), 0, "(buy) Vat dai: invalid value this");
        assertEq(vat.dai(address(someUser)), 0, "(buy) Vat dai: invalid value user");
        assertEq(dai.balanceOf(address(this)), gem.convertToAssets(100 * WAD), "(buy) Dai: invalid balance this");
        assertEq(dai.balanceOf(address(someUser)), gem.convertToAssets(5 * WAD), "(buy) Dai: invalid balance user");
        assertEq(vat.dai(vow), 0, "(buy) Vat dai: invalid value vow");
        (uint256 ink, uint256 art) = vat.urns(ILK, address(psm));
        assertEq(ink, gem.convertToAssets(60 * WAD), "(buy) Vat ink: invalid value psm");
        assertEq(art, gem.convertToAssets(60 * WAD), "(buy) Vat art: invalid value psm");
    }

    function testSwapBothOtherSmallFee() public {
        psm.file("tin", int256(1));
        psm.file("tout", int256(1));

        User user1 = new User(psm);
        gem.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);

        assertEq(gem.balanceOf(address(user1)), 0, "(sell) Gem: invalid balance user");
        assertEq(dai.balanceOf(address(user1)), gem.convertToAssets(40 * WAD - 40), "(sell) Dai: invalid balance user");
        assertEq(vat.dai(vow), gem.convertToAssets(40 * RAY), "(sell) Vat dai: invalid value vow");
        (uint256 ink1, uint256 art1) = vat.urns(ILK, address(psm));
        assertEq(ink1, gem.convertToAssets(40 * WAD), "(sell) Vat ink: invalid value psm");
        assertEq(art1, gem.convertToAssets(40 * WAD), "(sell) Vat art: invalid value psm");

        user1.buyGem(30 * ONE_USDX);

        assertEq(gem.balanceOf(address(user1)), 30 * ONE_USDX, "(buy) Gem: invalid balance user");
        assertApproxEqRel(
            dai.balanceOf(address(user1)),
            gem.convertToAssets((40 * WAD - 40) - (30 * WAD + 30)),
            10 ** 15, // Allow for 0.1% error margin
            "(buy) Dai: invalid balance user"
        );
        assertEq(vat.dai(vow), gem.convertToAssets((40 + 30)) * RAY, "(buy) Vat dai: invalid value vow");
        (uint256 ink2, uint256 art2) = vat.urns(ILK, address(psm));
        assertEq(ink2, gem.convertToAssets(10 * WAD), "(buy) Vat ink: invalid value psm");
        assertEq(art2, gem.convertToAssets(10 * WAD), "(buy) Vat art: invalid value psm");
    }

    function testSellGemInsufficientGem() public {
        User user1 = new User(psm);
        vm.expectRevert();
        user1.sellGem(40 * ONE_USDX);
    }

    function testSwapBothSmallFeeInsufficientDai() public {
        psm.file("tin", int256(1)); // Very small fee pushes you over the edge

        User user1 = new User(psm);
        gem.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);
        vm.expectRevert("Dai/insufficient-balance");
        user1.buyGem(40 * ONE_USDX);
    }

    function testSellGemOverLine() public {
        asset.mint(address(this), 1000 * ONE_USDX);
        gem.deposit(1000 * ONE_USDX, address(this));
        gem.approve(address(psm), type(uint256).max);
        assertEq(vat.Line(), 1000 * RAD);
        vm.expectRevert("Vat/ceiling-exceeded");
        psm.sellGem(address(this), 1001 * ONE_USDX);
    }

    function testTwoUsersInsufficientDai() public {
        User user1 = new User(psm);
        gem.transfer(address(user1), 40 * ONE_USDX);
        user1.sellGem(40 * ONE_USDX);

        User user2 = new User(psm);
        dai.mint(address(user2), 39 * WAD);
        vm.expectRevert("Dai/insufficient-balance");
        user2.buyGem(40 * ONE_USDX);
    }

    function testSwapBothZero() public {
        gem.approve(address(psm), type(uint256).max);
        psm.sellGem(address(this), 0);
        dai.approve(address(psm), type(uint256).max);
        psm.buyGem(address(this), 0);
    }

    function testRevertSwapWhenHalted() public {
        psm.file("tout", psm.SHALTED());
        vm.expectRevert("DssYieldBearingPsm/buy-gem-halted");
        psm.buyGem(address(this), 1);

        psm.file("tin", psm.SHALTED());
        vm.expectRevert("DssYieldBearingPsm/sell-gem-halted");
        psm.sellGem(address(this), 1);
    }

    event File(bytes32 indexed what, int256 data);
    event SellGem(address indexed owner, uint256 value, int256 fee, uint256 daiOut);
    event BuyGem(address indexed owner, uint256 value, int256 fee, uint256 daiIn);
}
