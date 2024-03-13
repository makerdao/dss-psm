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

import {DssInstance} from "dss-test/MCD.sol";
import {DssYieldBearingPsmInstance} from "./DssYieldBearingPsmInstance.sol";

struct DssYieldBearingPsmInitConfig {
    bytes32 psmKey;
    int256 tin;
    int256 tout;
    uint256 maxLine;
    uint256 gap;
    uint256 ttl;
    address pip;
    bytes32 pipKey;
}

interface DssPsmLike {
    function daiJoin() external view returns (address);
    function file(bytes32 what, int256 data) external;
    function file(bytes32 what, address data) external;
    function gem() external view returns (address);
    function ilk() external view returns (bytes32);
}

interface PipLike {
    function read() external view returns (bytes32);
    function poke(bytes32) external;
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
    function exec(bytes32) external returns (uint256);
    function setIlk(bytes32, uint256, uint256, uint256) external;
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
    function put(
        bytes32 _ilk,
        address _join,
        address _gem,
        uint256 _dec,
        uint256 _class,
        address _pip,
        address _xlip,
        string memory _name,
        string memory _symbol
    ) external;
}

library DssYieldBearingPsmInit {
    uint256 internal constant WAD = 10 ** 18;
    uint256 internal constant RAY = 10 ** 27;

    // New `IlkRegistry` class
    uint256 internal constant REG_CLASS_JOINLESS = 6;

    function init(
        DssInstance memory dss,
        DssYieldBearingPsmInstance memory inst,
        DssYieldBearingPsmInitConfig memory cfg
    ) internal {
        // Sanity checks
        require(cfg.gap > 0, "DssYieldBearingPsmInit/invalid-gap");
        require(DssPsmLike(inst.psm).daiJoin() == address(dss.daiJoin), "DssYieldBearingPsmInit/dai-join-mismatch");

        // 0. Initialize the pip to ensure its value is 1 WAD
        PipLike(cfg.pip).poke(bytes32(uint256(1 * WAD)));
        require(uint256(PipLike(cfg.pip).read()) == 1 * WAD, "DssYieldBearingPsmInit/invalid-pip-value");

        // 1. Initialize the new ilk
        bytes32 ilk = DssPsmLike(inst.psm).ilk();
        dss.vat.init(ilk);
        dss.jug.init(ilk);
        dss.spotter.file(ilk, "mat", 1 * RAY);
        dss.spotter.file(ilk, "pip", cfg.pip);
        dss.spotter.poke(ilk);

        // 2. Set auto-line for the new PSM.
        AutoLineLike autoLine = AutoLineLike(dss.chainlog.getAddress("MCD_IAM_AUTO_LINE"));
        autoLine.setIlk(ilk, cfg.maxLine, cfg.gap, cfg.ttl);
        autoLine.exec(ilk);

        // 3. Set PSM config params.
        DssPsmLike(inst.psm).file("tin", cfg.tin);
        DssPsmLike(inst.psm).file("tout", cfg.tout);
        DssPsmLike(inst.psm).file("vow", dss.chainlog.getAddress("MCD_VOW"));

        // 4. Add the new PSM to `IlkRegistry`
        IlkRegistryLike reg = IlkRegistryLike(dss.chainlog.getAddress("ILK_REGISTRY"));
        // Technically what is backing Dai is the underlying `asset`, not the `gem` itself.
        address asset = ERC4626Like(DssPsmLike(inst.psm).gem()).asset();
        reg.put(
            ilk,
            address(0), // No `gemJoin` for `yieldBearingPsm`
            asset,
            ERC20Like(asset).decimals(),
            REG_CLASS_JOINLESS,
            cfg.pip,
            address(0), // No `clip` for `yieldBearingPsm`
            ERC20Like(asset).name(),
            ERC20Like(asset).symbol()
        );

        // 5. Add the new PSM and the PIP to the chainlog.
        dss.chainlog.setAddress(cfg.psmKey, inst.psm);
        dss.chainlog.setAddress(cfg.pipKey, cfg.pip);
    }
}
