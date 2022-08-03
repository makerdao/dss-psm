# dss-psm

The official implementation of the [Peg Stability Module](https://forum.makerdao.com/t/mip29-peg-stability-module/5071).

### Psm

`Psm` allows you to either call `sellGem()` or `buyGem()` to trade ERC20 DAI for the gem or vice versa. Upon calling one of these functions the PSM vault will either lock gems in the join adapter, take out a dai loan and issue ERC20 DAI to the specified user or do that process in reverse.

`Psm` can charge either a positive or negative fee in both directions. Positive fees correspond to the user paying the protocol for using the PSM. Negative fees correspond to the protocol paying the user for using the PSM.

#### Approvals

The PSM requires ERC20 approvals to pull in the tokens.

To use `sellGem(usr, amt)` you must first call `gem.approve(<psmAddress>, amt)`. Example:

    // Trade 100 USDC for 100 DAI - fee
    usdc.approve(<psmAddress>, 100 * (10 ** 6));
    psm.sellGem(address(this), 100 * (10 ** 6));

To use `buyGem(usr, amt)` you must first call `dai.approve(<psmAddress>, amt + fee)`. Example:

    // Trade DAI + fee for 100 USDC
    uint256 WAD = 10 ** 18;
    dai.approve(<psmAddress>, 100 * (psm.tout() + WAD));
    psm.buyGem(address(this), 100 * (10 ** 6));

#### Notes on Fees

Please note the fee behaviour is not the same for both functions.

When calling `sellGem()`, DAI is minted at a 1:1 rate to which the fee is removed from that amount. So if you have 100 USDC with 1% fee and you call `sellGem()` then you will recieve `100 DAI - 1% * 100 DAI` = `99 DAI`. In this case the fee is subtracted from the result amount.

When calling `buyGem()`, you specify the amount of the gem you want to recieve. This fee is then added on top of this value to determine how much ERC20 DAI you require in your account. So if you call `buyGem()` for 100 USDC with a 1% fee then you require `100 DAI + 1% * 100 DAI` = `101 DAI`.

Please note this was a conscious decision to avoid dealing with decimal division and rounding leftovers. 

## Old Contracts [V1]

### Mainnet

USDC GemJoin: [0x0A59649758aa4d66E25f08Dd01271e891fe52199](https://etherscan.io/address/0x0A59649758aa4d66E25f08Dd01271e891fe52199#code)  
USDC PSM: [0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A](https://etherscan.io/address/0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A#code)  
USDP GemJoin: [0x7bbd8cA5e413bCa521C2c80D8d1908616894Cf21](https://etherscan.io/address/0x7bbd8cA5e413bCa521C2c80D8d1908616894Cf21#code)  
USDP PSM: [0x961Ae24a1Ceba861D1FDf723794f6024Dc5485Cf](https://etherscan.io/address/0x961Ae24a1Ceba861D1FDf723794f6024Dc5485Cf#code)  

### Kovan

USDC GemJoin: [0x4BA159Ad37FD80D235b4a948A8682747c74fDc0E](https://kovan.etherscan.io/address/0x4BA159Ad37FD80D235b4a948A8682747c74fDc0E#code)  
USDC PSM: [0xe4dC42e438879987e287A6d9519379936d7b065A](https://kovan.etherscan.io/address/0xe4dC42e438879987e287A6d9519379936d7b065A#code)  
