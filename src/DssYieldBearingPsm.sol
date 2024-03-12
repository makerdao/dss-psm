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

interface ERC20Like {
    function decimals() external view returns (uint8);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface ERC4626Like is ERC20Like {
    function asset() external view returns (address);
    function convertToAssets(uint256 shares) external view returns (uint256);
}

/**
 * @title A PSM for yield-bearing tokens.
 * @notice Swaps Dai for `gem` at a 1:1 exchange rate relative to the underlying `asset`.
 * @notice Fees `tin` and `tout` might apply.
 * @notice `tin` and `tout` can be negative, meaning the swaps are being subsidized by the protocol.
 * @dev No conversion between `gem` and its underlying `asset` is performed.
 * @dev A few assumptions are made:
 *      1. There are no other urns for the same `ilk`
 *      2. Stability fee is always zero for the `ilk`
 *      3. The `spot` price for `gem` underlying `asset` is always 1 (`10**27`).
 *      4. `spotter.par` (Dai parity) is always 1 (`10**27`).
 *      5. Emergency Shutdown threshold is set too high, so it cannot be activated.
 */
contract DssYieldBearingPsm {
    /// @notice Special value provided to indicate swaps are halted.
    /// @dev This value exists only for compatibility with callers that do not support signed `tin` and `tout`.
    uint256 public constant HALTED = type(uint256).max;
    /// @notice Special value for `tin` and/or `tout` to indicate swaps are halted.
    /// @dev Setting `tin` or `tout` to `type(int256).max` will cause sell gem and buy gem functions respectively to revert.
    int256 public constant SHALTED = type(int256).max;
    /// @notice Collateral type identifier.
    bytes32 public immutable ilk;
    /// @notice Dai token.
    ERC4626Like public immutable gem;
    /// @notice Maker Protocol core engine.
    VatLike public immutable vat;
    /// @notice Dai token.
    ERC20Like public immutable dai;
    /// @notice Dai adapter.
    DaiJoinLike public immutable daiJoin;
    /// @notice Precision conversion factor for `gem`'s underlying `asset`, since Dai is expected to always have 18 decimals.
    uint256 public immutable to18ConversionFactor;

    /// @notice Addresses with admin access on this contract. `wards[usr]`.
    mapping(address => uint256) public wards;
    /// @notice Fee for selling gems.
    /// @dev `wad` precision. 1 * WAD means a 100% fee. (-1 * 10 *16) means a -1% fee (subsidy).
    int256 public tin;
    /// @notice Fee for buying gems.
    /// @dev `wad` precision. 1 * WAD means a 100% fee. (-1 * 10 *16) means a -1% fee (subsidy).
    int256 public tout;
    /// @notice Maker Protocol balance sheet.
    address public vow;

    /// @dev Signed `wad` precision.
    int256 internal constant SWAD = 10 ** 18;
    /// @dev `ray` precision for `vat` manipulation.
    uint256 internal constant RAY = 10 ** 27;
    /// @dev Workaround to explicitly revert with an arithmetic error.
    string internal constant ARITHMETIC_ERROR = string(abi.encodeWithSignature("Panic(uint256)", 0x11));

    /**
     * @notice `usr` was granted admin access.
     * @param usr The user address.
     */
    event Rely(address indexed usr);
    /**
     * @notice `usr` admin access was revoked.
     * @param usr The user address.
     */
    event Deny(address indexed usr);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. ["vow"].
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, int256 data);
    /**
     * @notice A user sold `gem` for Dai.
     * @param owner The address receiving Dai.
     * @param value The amount of `gem` sold. [`gem` precision].
     * @param fee The fee (or subsidy) in Dai for the swap. [`wad`].
     * @param daiOut The amount of Dai the user received for the wap. [`wad`]
     */
    event SellGem(address indexed owner, uint256 value, int256 fee, uint256 daiOut);
    /**
     * @notice A user bought `gem` with Dai.
     * @param owner The address receiving `gem`.
     * @param value The amount of `gem` bought. [`gem` precision].
     * @param fee The fee (or subsidy) in Dai for the swap. [`wad`].
     * @param daiIn The amount of Dai the user sent for the wap. [`wad`]
     */
    event BuyGem(address indexed owner, uint256 value, int256 fee, uint256 daiIn);

    modifier auth() {
        require(wards[msg.sender] == 1, "DssYieldBearingPsm/not-authorized");
        _;
    }

    /**
     * @param _ilk The collateral type identifier.
     * @param _gem The gem to exchange with Dai.
     * @param _daiJoin The Dai adapter.
     */
    constructor(bytes32 _ilk, address _gem, address _daiJoin) {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        ilk = _ilk;
        gem = ERC4626Like(_gem);
        daiJoin = DaiJoinLike(_daiJoin);
        vat = VatLike(daiJoin.vat());
        dai = ERC20Like(daiJoin.dai());

        to18ConversionFactor = 10 ** (18 - ERC20Like(gem.asset()).decimals());

        dai.approve(_daiJoin, type(uint256).max);
        vat.hope(_daiJoin);
    }

    /*//////////////////////////////////
                    Math
    //////////////////////////////////*/

    ///@dev Safely converts `uint256` to `int256`. Reverts if it overflows.
    function _int256(uint256 x) internal pure returns (int256 y) {
        require((y = int256(x)) >= 0, ARITHMETIC_ERROR);
    }

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    /**
     * @notice Grants `usr` admin access to this contract.
     * @param usr The user address.
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract.
     * @param usr The user address.
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /**
     * @notice Updates a contract parameter.
     * @dev Swapping fees may not apply due to rounding errors for small swaps where
     *      `gemAmt < 10**gem.decimals() / tin` or
     *      `gemAmt < 10**gem.decimals() / tout`.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, int256 data) external auth {
        if (what == "tin") {
            require(data == SHALTED || (-SWAD <= data && data <= SWAD), "DssYieldBearingPsm/tin-out-of-range");
            tin = data;
        } else if (what == "tout") {
            require(data == SHALTED || (-SWAD <= data && data <= SWAD), "DssYieldBearingPsm/tout-out-of-range");
            tout = data;
        } else {
            revert("DssYieldBearingPsm/file-unrecognized-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Updates a contract parameter.
     * @dev This overload is designed as an adapter for callers that do not support signed `tin` and `tout`.
     *      It **SHOULD NOT** be called for regular values, as the only accepted value for `data` is `HALTED`.
     * @param what The changed parameter name. ["tin", "tout"].
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, uint256 data) external auth {
        if (what == "tin") {
            require(data == HALTED, "DssYieldBearingPsm/tin-out-of-range");
            tin = SHALTED;
        } else if (what == "tout") {
            require(data == HALTED, "DssYieldBearingPsm/tout-out-of-range");
            tout = SHALTED;
        } else {
            revert("DssYieldBearingPsm/file-unrecognized-param");
        }

        emit File(what, SHALTED);
    }
    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. ["vow"].
     * @param data The new value of the parameter.
     */

    function file(bytes32 what, address data) external auth {
        if (what == "vow") vow = data;
        else revert("DssYieldBearingPsm/file-unrecognized-param");

        emit File(what, data);
    }

    /*//////////////////////////////////
                  Swapping
    //////////////////////////////////*/

    /**
     * @notice Function that swaps `gem` into Dai.
     * @param usr The destination of the bought Dai.
     * @param gemAmt The amount of gem to sell. [`gem` precision].
     * @return daiOutWad The amount of Dai bought.
     */
    function sellGem(address usr, uint256 gemAmt) external returns (uint256 daiOutWad) {
        int256 tin_ = tin;
        require(tin_ != SHALTED, "DssYieldBearingPsm/sell-gem-halted");

        // NOTE: if `gem` and `asset` have different precision, we expect `gem.convertToAssets()` to return the value in `asset` precision.
        uint256 assetAmt18 = gem.convertToAssets(gemAmt) * to18ConversionFactor;
        int256 sAssetAmt18 = _int256(assetAmt18);

        // Transfer in gems and mint Dai
        require(gem.transferFrom(msg.sender, address(this), gemAmt), "DssYieldBearingPsm/gem-failed-transfer");
        vat.slip(ilk, address(this), sAssetAmt18);
        vat.frob(ilk, address(this), address(this), address(this), sAssetAmt18, sAssetAmt18);

        // Fee calculations
        int256 fee = sAssetAmt18 * tin_ / SWAD;
        if (fee >= 0) {
            // Positive fee - move fee to vow
            uint256 ufee = uint256(fee);
            daiOutWad = assetAmt18 - ufee;
            vat.move(address(this), vow, ufee * RAY);
        } else {
            // Negative fee - pay the user extra from the vow
            uint256 ufee = uint256(-fee);
            daiOutWad = assetAmt18 + ufee;
            vat.suck(vow, address(this), ufee * RAY);
        }
        daiJoin.exit(usr, daiOutWad);

        emit SellGem(usr, gemAmt, fee, daiOutWad);
    }

    /**
     * @notice Function that swaps Dai into `gem`.
     * @param usr The destination of the bought gems.
     * @param gemAmt The amount of gem to buy. [`gem` precision].
     * @return daiInWad The amount of Dai required to sell.
     */
    function buyGem(address usr, uint256 gemAmt) external returns (uint256 daiInWad) {
        int256 tout_ = tout;
        require(tout_ != SHALTED, "DssYieldBearingPsm/buy-gem-halted");

        // NOTE: if `gem` and `asset` have different precision, we expect `gem.convertToAssets()` to return the value in `asset` precision.
        uint256 assetAmt18 = gem.convertToAssets(gemAmt) * to18ConversionFactor;
        int256 sAssetAmt18 = _int256(assetAmt18);

        // Fee calculations
        int256 fee = sAssetAmt18 * tout_ / SWAD;
        if (fee >= 0) {
            // Positive fee - move fee to vow below after daiInWad comes in
            daiInWad = assetAmt18 + uint256(fee);
        } else {
            // Negative fee - pay the user extra from the vow
            uint256 ufee = uint256(-fee);
            daiInWad = assetAmt18 - ufee;
            vat.suck(vow, address(this), ufee * RAY);
        }

        // Transfer in Dai, repay loan and transfer out gems
        require(dai.transferFrom(msg.sender, address(this), daiInWad), "DssYieldBearingPsm/dai-failed-transfer");
        daiJoin.join(address(this), daiInWad);
        vat.frob(ilk, address(this), address(this), address(this), -sAssetAmt18, -sAssetAmt18);
        vat.slip(ilk, address(this), -sAssetAmt18);
        require(gem.transfer(usr, gemAmt), "DssYieldBearingPsm/gem-failed-transfer");
        if (fee >= 0) {
            vat.move(address(this), vow, uint256(fee) * RAY);
        }

        emit BuyGem(usr, gemAmt, fee, daiInWad);
    }
}
