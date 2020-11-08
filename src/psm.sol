pragma solidity >=0.5.12;

import { VatAbstract } from "dss-interfaces/dss/VatAbstract.sol";
import { VowAbstract } from "dss-interfaces/dss/VowAbstract.sol";
import "dss/lib.sol";

// Peg Stability Module - sits between any join adapter and the vat
// Allows anyone to go between Dai and the Gem by pooling the liquidity
// An optional fee is charged for incoming and outgoing transfers

contract DssPsm is LibNote {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    VatAbstract public vat;
    address public vow;
    uint256 public tin;         // toll in [wad]
    uint256 public tout;        // toll out [wad]

    // --- Init ---
    constructor(address vat_, address vow_) public {
        wards[msg.sender] = 1;
        vat = VatAbstract(vat_);
        vow = vow_;
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external note auth {
        if (what == "tin") tin = data;
        else if (what == "tout") tout = data;
        else revert("DssPsm/file-unrecognized-param");
    }

    function slip(bytes32 ilk, address usr, int256 wad) external note auth {
        if (wad >= 0) {
            // Incoming
            uint256 uwad = uint256(wad);
            uint256 fee = mul(uwad, tin) / WAD;
            uint256 base = sub(uwad, fee);
            vat.slip(ilk, address(this), wad);
            vat.frob(ilk, address(this), address(this), usr, int256(base), int256(base));
            vat.frob(ilk, address(this), address(this), vow, int256(fee), int256(fee));
        } else {
            // Outgoing
            uint256 uwad = uint256(-wad);
            uint256 fee = mul(uwad, tout) / WAD;
            uint256 base = sub(uwad, fee);
            vat.move(usr, vow, fee);
            vat.frob(ilk, address(this), address(this), usr, -int256(base), -int256(base));
            vat.slip(ilk, address(this), -int256(base));
        }
    }

}
