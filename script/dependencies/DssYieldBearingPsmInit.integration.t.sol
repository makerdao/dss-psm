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
import {DssYieldBearingPsm} from "src/DssYieldBearingPsm.sol";
import {DssValue} from "src/mocks/DssValue.sol";
import {TokenMock} from "src/mocks/TokenMock.sol";
import {YieldBearingTokenMock} from "src/mocks/YieldBearingTokenMock.sol";
import {DssYieldBearingPsmDeploy, DssYieldBearingPsmDeployParams} from "./DssYieldBearingPsmDeploy.sol";
import {DssYieldBearingPsmInstance} from "./DssYieldBearingPsmInstance.sol";
import {DssYieldBearingPsmInit, DssYieldBearingPsmInitConfig} from "./DssYieldBearingPsmInit.sol";

interface ProxyLike {
    function exec(address usr, bytes memory fax) external returns (bytes memory out);
}

interface ERC20Like {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface ERC4626Like is ERC20Like {
    function asset() external view returns (address);
}

interface AutoLineLike {
    function ilks(bytes32) external view returns (uint256 line, uint256 gap, uint48 ttl, uint48 last, uint48 lastInc);
}

interface IlkRegistryLike {
    function info(bytes32 ilk)
        external
        view
        returns (
            string memory name,
            string memory symbol,
            uint256 class,
            uint256 dec,
            address gem,
            address pip,
            address join,
            address xlip
        );
}

contract InitCaller {
    function init(
        DssInstance memory dss,
        DssYieldBearingPsmInstance memory inst,
        DssYieldBearingPsmInitConfig memory cfg
    ) external {
        DssYieldBearingPsmInit.init(dss, inst, cfg);
    }
}

contract DssYieldBearingPsmInitTest is DssTest {
    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    bytes32 constant ILK = "PSM-SUSDX-A";
    bytes32 constant PSM_KEY = "MCD_PSM_SUSDX_A";
    bytes32 constant PIP_KEY = "PIP_USDX";
    uint256 constant REG_CLASS_JOINLESS = 6; // New `IlkRegistry` class

    DssInstance dss;
    address pause;
    address vow;
    address chief;
    IlkRegistryLike reg;
    ProxyLike pauseProxy;
    AutoLineLike autoLine;
    DssYieldBearingPsmInstance inst;
    DssYieldBearingPsmInitConfig cfg;
    DssYieldBearingPsm psm;
    address gem;
    InitCaller caller;
    DssValue pip;

    function setUp() public {
        vm.createSelectFork("mainnet");

        dss = MCD.loadFromChainlog(CHAINLOG);

        pause = dss.chainlog.getAddress("MCD_PAUSE");
        vow = dss.chainlog.getAddress("MCD_VOW");
        reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));
        pauseProxy = ProxyLike(dss.chainlog.getAddress("MCD_PAUSE_PROXY"));
        chief = dss.chainlog.getAddress("MCD_ADM");
        autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        gem = address(new YieldBearingTokenMock(address(new TokenMock("USDX", "USDX")), "SUSDX", "SUSDX"));
        pip = new DssValue();
        // pip.poke(bytes32(uint256(1 * WAD)));
        pip.rely(address(pauseProxy));

        caller = new InitCaller();

        inst = DssYieldBearingPsmDeploy.deploy(
            DssYieldBearingPsmDeployParams({
                deployer: address(this),
                owner: address(pauseProxy),
                ilk: ILK,
                gem: gem,
                daiJoin: address(dss.daiJoin)
            })
        );

        psm = DssYieldBearingPsm(inst.psm);

        cfg = DssYieldBearingPsmInitConfig({
            psmKey: PSM_KEY,
            tin: 0.01 ether,
            tout: 0.01 ether,
            maxLine: 1_000_000_000 * RAD,
            gap: 100_000_000 * RAD,
            ttl: 8 hours,
            pipKey: PIP_KEY,
            pip: address(pip)
        });

        vm.label(CHAINLOG, "Chainlog");
        vm.label(pause, "Pause");
        vm.label(vow, "Vow");
        vm.label(inst.psm, "YieldBearingPsm");
        vm.label(address(pauseProxy), "PauseProxy");
        vm.label(address(dss.vat), "Vat");
        vm.label(address(dss.jug), "Jug");
        vm.label(address(dss.spotter), "Spotter");
        vm.label(address(dss.dai), "Dai");
        vm.label(address(dss.daiJoin), "DaiJoin");
        vm.label(address(autoLine), "AutoLine");
        vm.label(address(pip), "Pip");
    }

    function testYieldBearingPsmOnboarding() public {
        // Simulate a spell casting
        vm.prank(pause);
        pauseProxy.exec(address(caller), abi.encodeCall(caller.init, (dss, inst, cfg)));

        // Sanity checks
        {
            assertEq(psm.tin(), cfg.tin, "after: invalid tin");
            assertEq(psm.tout(), cfg.tout, "after: invalid tout");
            assertEq(psm.vow(), vow, "after: invalid vow");
        }

        // New PSM is present in AutoLine
        {
            (uint256 maxLine, uint256 gap, uint48 ttl, uint256 last, uint256 lastInc) = autoLine.ilks(ILK);
            assertEq(maxLine, cfg.maxLine, "after: AutoLine invalid maxLine");
            assertEq(gap, cfg.gap, "after: AutoLine invalid gap");
            assertEq(ttl, uint48(cfg.ttl), "after: AutoLine invalid ttl");
            assertEq(last, block.number, "after: AutoLine invalid last");
            assertEq(lastInc, block.timestamp, "after: AutoLine invalid lastInc");
        }

        // PSM info is added to IlkRegistry
        {
            (
                string memory name,
                string memory symbol,
                uint256 _class,
                uint256 dec,
                address _gem,
                address _pip,
                address gemJoin,
                address xlip
            ) = reg.info(ILK);

            assertEq(name, ERC20Like(ERC4626Like(gem).asset()).name(), "after: reg name mismatch");
            assertEq(symbol, ERC20Like(ERC4626Like(gem).asset()).symbol(), "after: reg symbol mismatch");
            assertEq(_class, REG_CLASS_JOINLESS, "after: reg class mismatch");
            assertEq(dec, ERC20Like(ERC4626Like(gem).asset()).decimals(), "after: reg dec mismatch");
            assertEq(_gem, ERC4626Like(gem).asset(), "after: reg gem mismatch");
            assertEq(_pip, cfg.pip, "after: reg pip mismatch");
            assertEq(gemJoin, address(0), "after: invalid reg gemJoin");
            assertEq(xlip, address(0), "after: invalid reg xlip");
        }

        // PSM and PIP present in Chainlog
        {
            assertEq(dss.chainlog.getAddress(cfg.psmKey), inst.psm, "after: `psm` not in chainlog");
            assertEq(dss.chainlog.getAddress(cfg.pipKey), cfg.pip, "after: `pip` not in chainlog");
        }
    }
}
