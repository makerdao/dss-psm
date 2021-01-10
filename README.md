# DssPsm

The official implementation of the [Peg Stability Module](https://forum.makerdao.com/t/mip29-peg-stability-module/5071). There are two main components to the PSM:

### AuthGemJoinX

This is an exact duplicate of the `GemJoinX` adapter for the given collateral type with two modifications.

First the method signature of `join()` is changed to include the original message sender at the end as well as adding the `auth` modifier. This should look like:

`function join(address urn, uint256 wad) external note` -> `function join(address urn, uint256 wad, address _msgSender) external note auth`

Second, all instances of `msg.sender` are replaced with `_msgSender` in the `join()` function.

In this repository I have added [join-5-auth.sol](https://github.com/BellwoodStudios/dss-psm/blob/master/src/join-5-auth.sol) for the PSM-friendly version of [join-5.sol](https://github.com/makerdao/dss-gem-joins/blob/master/src/join-5.sol) which is used for USDC. This can be applied to any other gem join adapter.

### DssPsm

This is the actual PSM module which acts as a authed special vault sitting behind the `AuthGemJoinX` contract. `DssPsm` allows you to either call `sellGem()` or `buyGem()` to trade ERC20 DAI for the gem or vice versa. Upon calling one of these functions the PSM vault will either lock gems in the join adapter, take out a dai loan and issue ERC20 DAI to the specified user or do that process in reverse.

#### Approvals

The PSM requires ERC20 approvals to pull in the tokens.

To use `sellGem(usr, amt)` you must first call `gem.approve(<gemJoinAddress>, amt)`. Example:

    // Trade 100 USDC for 100 DAI - fee
    usdc.approve(0x0A59649758aa4d66E25f08Dd01271e891fe52199, 100 * (10 ** 6));
    psm.sellGem(address(this), 100 * (10 ** 6));

To use `buyGem(usr, amt)` you must first call `dai.approve(<psmAddress>, amt + fee)`. Example:

    // Trade DAI + fee for 100 USDC
    uint256 WAD = 10 ** 18;
    dai.approve(0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A, 100 * (psm.tout() + WAD));
    psm.buyGem(address(this), 100 * (10 ** 6));

#### Notes on Fees

Please note the fee behaviour is not the same for both functions.

When calling `sellGem()`, DAI is minted at a 1:1 rate to which the fee is removed from that amount. So if you have 100 USDC with 1% fee and you call `sellGem()` then you will recieve `100 DAI - 1% * 100 DAI` = `99 DAI`. In this case the fee is subtracted from the result amount.

When calling `buyGem()`, you specify the amount of the gem you want to recieve. This fee is then added on top of this value to determine how much ERC20 DAI you require in your account. So if you call `buyGem()` for 100 USDC with a 1% fee then you require `100 DAI + 1% * 100 DAI` = `101 DAI`.

Please note this was a conscious decision to avoid dealing with decimal division and rounding leftovers. 

## Contracts

### Mainnet

GemJoin: [0x0A59649758aa4d66E25f08Dd01271e891fe52199](https://etherscan.io/address/0x0A59649758aa4d66E25f08Dd01271e891fe52199#code)  
PSM: [0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A](https://etherscan.io/address/0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A#code)  

### Kovan

GemJoin: [0x4BA159Ad37FD80D235b4a948A8682747c74fDc0E](https://kovan.etherscan.io/address/0x4BA159Ad37FD80D235b4a948A8682747c74fDc0E#code)  
PSM: [0xe4dC42e438879987e287A6d9519379936d7b065A](https://kovan.etherscan.io/address/0xe4dC42e438879987e287A6d9519379936d7b065A#code)  