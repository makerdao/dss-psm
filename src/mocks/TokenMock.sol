// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract TokenMock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
