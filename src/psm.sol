pragma solidity ^0.6.7;

import { VatAbstract } from "dss-interfaces/dss/VatAbstract.sol";

contract DssPsm {

    VatAbstract public vat;

    constructor(address vat_) {
        vat = vat_;
    }

    function slip(bytes32 ilk, address usr, int256 wad) external note auth {
        gem[ilk][usr] = add(gem[ilk][usr], wad);
    }

}
