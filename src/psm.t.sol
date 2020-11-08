pragma solidity >=0.5.12;

import "ds-test/test.sol";

import "./psm.sol";

contract DssPsmTest is DSTest {
    DssPsm psm;

    function setUp() public {
        psm = new DssPsm(address(0), address(0));
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
