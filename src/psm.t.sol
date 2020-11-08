pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./DssPsm.sol";

contract DssPsmTest is DSTest {
    DssPsm psm;

    function setUp() public {
        psm = new DssPsm();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
