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

import { DSTokenAbstract } from "dss-interfaces/Interfaces.sol";

import {Psm} from "../Psm.sol";

contract PsmIntegrationTest is DSSTest {

    using GodMode for *;

    DSTokenAbstract public usdc;

    Psm psm;

    bytes32 constant ILK = "PSM-USDC-X";
    int256 constant TOLL_ONE_PCT = 10 ** 16;
    uint256 constant ONE_USDC = 10 ** 6;

    function setupEnv() internal virtual override returns (MCD) {
        return autoDetectEnv();
    }

    function postSetup() internal virtual override {
        usdc = DSTokenAbstract(mcd.chainlog().getAddress("USDC"));

        psm = new Psm(ILK, address(usdc), address(mcd.daiJoin()));
        psm.file("vow", address(mcd.vow()));

        mcd.giveAdminAccess();
        mcd.initIlk(ILK, address(psm));
        mcd.vat().file(ILK, "line", 100 * RAD);

        usdc.setBalance(address(this), 200 * ONE_USDC);
        usdc.approve(address(psm), type(uint256).max);
        mcd.dai().approve(address(psm), type(uint256).max);
    }

    function testSwapNoFees() public {
        assertEq(usdc.balanceOf(address(this)), 200 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 0);
        (uint256 ink, uint256 art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 0);
        assertEq(art, 0);

        psm.sellGem(address(this), 50 * ONE_USDC);

        assertEq(usdc.balanceOf(address(this)), 150 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 50 ether);
        (ink, art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 50 ether);
        assertEq(art, 50 ether);

        psm.buyGem(address(this), 25 * ONE_USDC);

        assertEq(usdc.balanceOf(address(this)), 175 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 25 ether);
        (ink, art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 25 ether);
        assertEq(art, 25 ether);
    }

    function testSwapFees() public {
        psm.file("tin", 10 * TOLL_ONE_PCT);
        psm.file("tout", 10 * TOLL_ONE_PCT);
        uint256 vowDai = mcd.vat().dai(address(mcd.vow()));

        assertEq(usdc.balanceOf(address(this)), 200 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 0);
        (uint256 ink, uint256 art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 0);
        assertEq(art, 0);

        psm.sellGem(address(this), 50 * ONE_USDC);

        assertEq(usdc.balanceOf(address(this)), 150 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 45 ether);
        (ink, art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 50 ether);
        assertEq(art, 50 ether);
        assertEq(mcd.vat().dai(address(mcd.vow())), vowDai + 5 * RAD);

        psm.buyGem(address(this), 30 * ONE_USDC);

        assertEq(usdc.balanceOf(address(this)), 180 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 12 ether);
        (ink, art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 20 ether);
        assertEq(art, 20 ether);
        assertEq(mcd.vat().dai(address(mcd.vow())), vowDai + 8 * RAD);
    }

    function testSwapNegativeFees() public {
        psm.file("tin", -10 * TOLL_ONE_PCT);
        psm.file("tout", -10 * TOLL_ONE_PCT);
        uint256 vowSin = mcd.vat().sin(address(mcd.vow()));

        assertEq(usdc.balanceOf(address(this)), 200 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 0);
        (uint256 ink, uint256 art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 0);
        assertEq(art, 0);

        psm.sellGem(address(this), 50 * ONE_USDC);

        assertEq(usdc.balanceOf(address(this)), 150 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 55 ether);
        (ink, art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 50 ether);
        assertEq(art, 50 ether);
        assertEq(mcd.vat().sin(address(mcd.vow())), vowSin + 5 * RAD);

        psm.buyGem(address(this), 30 * ONE_USDC);

        assertEq(usdc.balanceOf(address(this)), 180 * ONE_USDC);
        assertEq(mcd.dai().balanceOf(address(this)), 28 ether);
        (ink, art) = mcd.vat().urns(ILK, address(psm));
        assertEq(ink, 20 ether);
        assertEq(art, 20 ether);
        assertEq(mcd.vat().sin(address(mcd.vow())), vowSin + 8 * RAD);
    }

    function testExit() public {
        // Max out the PSM
        psm.sellGem(address(this), 100 * ONE_USDC);

        // ... Global Settlement results in us having gems ...
        mcd.vat().slip(ILK, address(this), int256(50 ether));

        // Can exit at 1:1
        assertEq(mcd.vat().gem(ILK, address(this)), 50 ether);
        assertEq(usdc.balanceOf(address(123)), 0);

        psm.exit(address(123), 50 * ONE_USDC);

        assertEq(mcd.vat().gem(ILK, address(this)), 0);
        assertEq(usdc.balanceOf(address(123)), 50 * ONE_USDC);
    }
    
}
