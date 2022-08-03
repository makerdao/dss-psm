// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

contract SpotterMock {
    mapping (bytes32 => address) private _ilks;
    function setPip(bytes32 ilk, address pip) external {
        _ilks[ilk] = pip;
    }
    function ilks(bytes32 ilk) external view returns (address, uint256) {
        return (_ilks[ilk], 10 ** 27);
    }
}
