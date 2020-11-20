pragma solidity >=0.5.12;

interface FileLike {
    function file(bytes32, uint256) external;
}

// Perform linear interpolation on a dss administrative value over time

contract Lerp {

    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    uint256 constant WAD = 10 ** 18;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    FileLike immutable public target;
    bytes32 immutable public what;
    uint256 immutable public start;
    uint256 immutable public end;
    uint256 immutable public duration;

    bool public started;
    bool public done;
    uint256 public startTime;
    
    constructor(address target_, bytes32 what_, uint256 start_, uint256 end_, uint256 duration_) public {
        require(duration_ != 0, "Lerp/no-zero-duration");
        require(start_ != end_, "Lerp/start-end-equal");
        target = FileLike(target_);
        what = what_;
        start = start_;
        end = end_;
        duration = duration_;
        started = false;
        done = false;
        wards[msg.sender] = 1;
    }

    function init() external auth {
        require(!started, "Lerp/already-started");
        require(!done, "Lerp/finished");
        target.file(what, start);
        startTime = block.timestamp;
        started = true;
    }

    function tick() external {
        require(started, "Lerp/not-started");
        require(block.timestamp > startTime, "Lerp/no-time-elasped");
        require(!done, "Lerp/finished");
        if (block.timestamp < startTime + duration) {
            // This will not overflow unless start or end is really large
            uint256 t = mul(WAD, sub(block.timestamp, startTime)) / duration;
            target.file(what, sub(add(mul(end, t) / WAD, start), mul(start, t) / WAD));
        } else {
            target.file(what, end);
            done = true;
        }
    }

}