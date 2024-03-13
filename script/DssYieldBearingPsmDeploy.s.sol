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

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {MCD, DssInstance} from "dss-test/MCD.sol";
import {ScriptTools} from "dss-test/ScriptTools.sol";
import {DssYieldBearingPsmDeploy, DssYieldBearingPsmDeployParams} from "./dependencies/DssYieldBearingPsmDeploy.sol";
import {DssYieldBearingPsmInstance} from "./dependencies/DssYieldBearingPsmInstance.sol";

contract DssYieldBearingPsmDeployScript is Script {
    using stdJson for string;
    using ScriptTools for string;

    string constant NAME = "dss-psm-deploy";
    string config;

    address constant CHAINLOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    DssInstance dss = MCD.loadFromChainlog(CHAINLOG);
    address pauseProxy = dss.chainlog.getAddress("MCD_PAUSE_PROXY");
    string ilkStr;
    bytes32 ilk;
    address gem;
    DssYieldBearingPsmInstance inst;

    function run() external {
        config = ScriptTools.loadConfig();

        ilkStr = config.readString(".ilk", "FOUNDRY_ILK");
        ilk = ilkStr.stringToBytes32();
        gem = config.readAddress(".gem", "FOUNDRY_GEM");

        vm.startBroadcast();

        inst = DssYieldBearingPsmDeploy.deploy(
            DssYieldBearingPsmDeployParams({
                deployer: msg.sender,
                owner: pauseProxy,
                ilk: ilk,
                gem: gem,
                daiJoin: address(dss.daiJoin)
            })
        );

        vm.stopBroadcast();

        ScriptTools.exportContract(NAME, "psm", inst.psm);
        ScriptTools.exportContract(NAME, "gem", gem);
        ScriptTools.exportValue(NAME, "ilk", ilkStr);
    }
}
