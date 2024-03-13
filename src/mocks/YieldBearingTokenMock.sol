// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.16;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract YieldBearingTokenMock is ERC4626 {
    constructor(address asset, string memory name, string memory symbol) ERC4626(ERC20(asset), name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
