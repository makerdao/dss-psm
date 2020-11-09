pragma solidity >=0.5.12;

import "ds-test/test.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";
import {Vat}              from "dss/vat.sol";
import {Spotter}          from "dss/spot.sol";
import {Vow}              from "dss/vow.sol";
import {GemJoin, DaiJoin} from "dss/join.sol";
import {Dai}              from "dss/dai.sol";

import "./psm.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract TestVat is Vat {
    function mint(address usr, uint256 rad) public {
        dai[usr] += rad;
    }
}

contract TestVow is Vow {
    constructor(address vat, address flapper, address flopper)
        public Vow(vat, flapper, flopper) {}
    // Total deficit
    function Awe() public view returns (uint256) {
        return vat.sin(address(this));
    }
    // Total surplus
    function Joy() public view returns (uint256) {
        return vat.dai(address(this));
    }
    // Unqueued, pre-auction debt
    function Woe() public view returns (uint256) {
        return sub(sub(Awe(), Sin), Ash);
    }
}

contract User {

    Vat public vat;
    GemJoin public gemJoin;

    constructor(Vat vat_, GemJoin gemJoin_) public {
        vat = vat_;
        gemJoin = gemJoin_;
    }

    function join(uint256 wad) public {
        gemJoin.join(address(this), wad);
    }

    function exit(uint256 wad) public {
        vat.hope(address(gemJoin.vat()));
        gemJoin.exit(address(this), wad);
    }

}

contract DssPsmTest is DSTest {
    
    Hevm hevm;

    address me;

    TestVat vat;
    Spotter spot;
    TestVow vow;
    DSValue pip;
    GemJoin gemA;
    DSToken usdx;
    DaiJoin daiJoin;
    Dai dai;

    DssPsm psmA;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    bytes32 constant ilk = "usdx";

    uint256 constant TOLL_ONE_PCT = 10 ** 16;

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        vat = new TestVat();
        vat = vat;

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vow = new TestVow(address(vat), address(0), address(0));

        usdx = new DSToken("GEM");
        usdx.mint(1000 ether);

        vat.init(ilk);

        psmA = new DssPsm(address(vat), address(vow));
        gemA = new GemJoin(address(psmA), ilk, address(usdx));
        vat.rely(address(psmA));
        psmA.rely(address(gemA));
        usdx.approve(address(gemA));

        pip = new DSValue();
        pip.poke(bytes32(uint256(1 ether))); // Spot = $1

        spot.file(ilk, bytes32("pip"), address(pip));
        spot.file(ilk, bytes32("mat"), ray(1 ether));
        spot.poke(ilk);

        vat.file(ilk, "line", rad(1000 ether));
        vat.file("Line",      rad(1000 ether));
    }

    function test_join_no_fee() public {
        assertEq(usdx.balanceOf(me), 1000 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), 0);
        assertEq(vow.Joy(), 0);

        gemA.join(me, 100 ether);

        assertEq(usdx.balanceOf(me), 900 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), rad(100 ether));
        assertEq(vow.Joy(), 0);
        (uint256 inkme, uint256 artme) = vat.urns(ilk, me);
        assertEq(inkme, 0);
        assertEq(artme, 0);
        (uint256 inkpsm, uint256 artpsm) = vat.urns(ilk, address(psmA));
        assertEq(inkpsm, 100 ether);
        assertEq(artpsm, 100 ether);
    }

    function test_join_fee() public {
        psmA.file("tin", TOLL_ONE_PCT);

        assertEq(usdx.balanceOf(me), 1000 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), 0);
        assertEq(vow.Joy(), 0);

        gemA.join(me, 100 ether);

        assertEq(usdx.balanceOf(me), 900 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), rad(99 ether));
        assertEq(vow.Joy(), rad(1 ether));
    }

    function test_join_exit_no_fee() public {
        gemA.join(me, 100 ether);
        vat.hope(address(psmA));
        gemA.exit(me, 40 ether);

        assertEq(usdx.balanceOf(me), 940 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), rad(60 ether));
        assertEq(vow.Joy(), 0);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(psmA));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }

    function test_join_exit_fees() public {
        psmA.file("tin", 5 * TOLL_ONE_PCT);
        psmA.file("tout", 10 * TOLL_ONE_PCT);

        gemA.join(me, 100 ether);

        assertEq(usdx.balanceOf(me), 900 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), rad(95 ether));
        assertEq(vow.Joy(), rad(5 ether));
        (uint256 ink1, uint256 art1) = vat.urns(ilk, address(psmA));
        assertEq(ink1, 100 ether);
        assertEq(art1, 100 ether);

        vat.hope(address(psmA));
        gemA.exit(me, 40 ether);

        assertEq(usdx.balanceOf(me), 940 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), rad(51 ether));
        assertEq(vow.Joy(), rad(9 ether));
        (uint256 ink2, uint256 art2) = vat.urns(ilk, address(psmA));
        assertEq(ink2, 60 ether);
        assertEq(art2, 60 ether);
    }

    function test_join_other_exit() public {
        gemA.join(me, 100 ether);

        assertEq(usdx.balanceOf(me), 900 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.dai(me), rad(100 ether));
        assertEq(vow.Joy(), rad(0 ether));

        User someUser = new User(vat, gemA);
        vat.mint(address(someUser), rad(45 ether));
        someUser.exit(40 ether);

        assertEq(usdx.balanceOf(me), 900 ether);
        assertEq(usdx.balanceOf(address(someUser)), 40 ether);
        assertEq(vat.gem(ilk, me), 0 ether);
        assertEq(vat.gem(ilk, address(someUser)), 0 ether);
        assertEq(vat.dai(me), rad(100 ether));
        assertEq(vat.dai(address(someUser)), rad(5 ether));
        assertEq(vow.Joy(), rad(0 ether));
        (uint256 ink, uint256 art) = vat.urns(ilk, address(psmA));
        assertEq(ink, 60 ether);
        assertEq(art, 60 ether);
    }
    
}
