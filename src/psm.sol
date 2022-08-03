// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2020-2022 Dai Foundation
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

interface VatLike {
    function hope(address) external;
    function nope(address) external;
    function move(address, address, uint256) external;
    function slip(bytes32, address, int256) external;
    function frob(bytes32, address, address, address, int256, int256) external;
    function suck(address, address, uint256) external;
}

interface DaiJoinLike {
    function vat() external view returns (address);
    function dai() external view returns (address);
    function join(address, uint256) external;
    function exit(address, uint256) external;
}

interface TokenLike {
    function decimals() external view returns (uint8);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

// Peg Stability Module
// Allows anyone to go between Dai and the Gem by pooling the liquidity
// An optional fee is charged for incoming and outgoing transfers

contract Psm {

    // --- Data ---
    mapping (address => uint256) public wards;

    int256 public tin;      // toll in  [wad]
    int256 public tout;     // toll out [wad]
    address public vow;

    bytes32     immutable public ilk;
    TokenLike   immutable public gem;
    VatLike     immutable public vat;
    TokenLike   immutable public dai;
    DaiJoinLike immutable public daiJoin;

    uint256 immutable private to18ConversionFactor;

    int256 constant SWAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, int256 data);
    event File(bytes32 indexed what, address data);
    event SellGem(address indexed owner, uint256 value, int256 fee);
    event BuyGem(address indexed owner, uint256 value, int256 fee);
    event Exit(address indexed usr, uint256 amt);

    modifier auth {
        require(wards[msg.sender] == 1, "Psm/not-authorized");
        _;
    }

    constructor(bytes32 _ilk, address _gem, address _daiJoin) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        
        ilk = _ilk;
        gem = TokenLike(_gem);
        daiJoin = DaiJoinLike(_daiJoin);
        vat = VatLike(daiJoin.vat());
        dai = TokenLike(daiJoin.dai());

        to18ConversionFactor = 10 ** (18 - gem.decimals());

        dai.approve(_daiJoin, type(uint256).max);
        vat.hope(_daiJoin);
    }

    // --- Administration ---
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function file(bytes32 what, int256 data) external auth {
        require(-SWAD <= data && data <= SWAD, "Psm/out-of-range");

        if (what == "tin") tin = data;
        else if (what == "tout") tout = data;
        else revert("Psm/file-unrecognized-param");

        emit File(what, data);
    }

    function file(bytes32 what, address data) external auth {
        if (what == "vow") vow = data;
        else revert("Psm/file-unrecognized-param");

        emit File(what, data);
    }

    // --- Primary Functions ---
    function sellGem(address usr, uint256 gemAmt) external {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        require(int256(gemAmt18) >= 0, "Psm/overflow");

        // Transfer in gems and mint dai
        require(gem.transferFrom(msg.sender, address(this), gemAmt), "Psm/failed-transfer");
        vat.slip(ilk, address(this), int256(gemAmt18));
        vat.frob(ilk, address(this), address(this), address(this), int256(gemAmt18), int256(gemAmt18));

        // Fee calculations
        int256 fee = int256(gemAmt18) * tin / SWAD;
        uint256 daiAmt;
        if (fee >= 0) {
            // Positive fee - move fee to vow
            // NOTE: we exclude the case where ufee > gemAmt18 in the tin file constraint
            uint256 ufee = uint256(fee);
            daiAmt = gemAmt18 - ufee;
            vat.move(address(this), vow, ufee * RAY);
        } else {
            // Negative fee - pay the user extra from the vow
            uint256 ufee = uint256(-fee);
            daiAmt = gemAmt18 + ufee;
            vat.suck(vow, address(this), ufee * RAY);
        }
        daiJoin.exit(usr, daiAmt);

        emit SellGem(usr, gemAmt, fee);
    }

    function buyGem(address usr, uint256 gemAmt) external {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        require(int256(gemAmt18) >= 0, "Psm/overflow");

        // Fee calculations
        int256 fee = int256(gemAmt18) * tout / SWAD;
        uint256 daiAmt;
        if (fee >= 0) {
            // Positive fee - move fee to vow below after daiAmt comes in
            daiAmt = gemAmt18 + uint256(fee);
        } else {
            // Negative fee - pay the user extra from the vow
            // NOTE: we exclude the case where ufee > gemAmt18 in the tout file constraint
            uint256 ufee = uint256(-fee);
            daiAmt = gemAmt18 - ufee;
            vat.suck(vow, address(this), ufee * RAY);
        }

        // Transfer in dai, repay loan and transfer out gems
        require(dai.transferFrom(msg.sender, address(this), daiAmt), "Psm/failed-transfer");
        daiJoin.join(address(this), daiAmt);
        vat.frob(ilk, address(this), address(this), address(this), -int256(gemAmt18), -int256(gemAmt18));
        vat.slip(ilk, address(this), -int256(gemAmt18));
        require(gem.transfer(usr, gemAmt), "Psm/failed-transfer");
        if (fee >= 0) {
            vat.move(address(this), vow, uint256(fee) * RAY);
        }

        emit BuyGem(usr, gemAmt, fee);
    }

    // --- Global Settlement Support ---
    function exit(address usr, uint256 gemAmt) external {
        uint256 gemAmt18 = gemAmt * to18ConversionFactor;
        require(int256(gemAmt18) >= 0, "Psm/overflow");

        vat.slip(ilk, msg.sender, -int256(gemAmt18));
        require(gem.transfer(usr, gemAmt), "Psm/failed-transfer");

        emit Exit(usr, gemAmt);
    }

}
