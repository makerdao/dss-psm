# dss-psm

The official implementation of the [Peg Stability Module](https://forum.makerdao.com/t/mip29-peg-stability-module/5071).

### Psm

`Psm` allows you to either call `sellGem()` or `buyGem()` to trade ERC20 DAI for the gem or vice versa. Upon calling one of these functions the PSM vault will either lock gems in the join adapter, take out a dai loan and issue ERC20 DAI to the specified user or do that process in reverse.

`Psm` can charge either a positive or negative fee in both directions. Positive fees correspond to the user paying the protocol for using the PSM. Negative fees correspond to the protocol paying the user for using the PSM.

This `Psm` implementation enables ERC4626 gems (yield-bearing tokens), so the protocol can accrue yield automatically for the funds held in it.

#### Approvals

The PSM requires ERC20 approvals to pull in the tokens.

To use `sellGem(usr, amt)` you must first call `gem.approve(<psmAddress>, amt)`. Example:

    // Trade 100 $STABLE for 100 DAI - fee
    usdc.approve(<psmAddress>, 100 * (10 ** 6));
    psm.sellGem(address(this), 100 * (10 ** 6));

To use `buyGem(usr, amt)` you must first call `dai.approve(<psmAddress>, amt + fee)` or `dai.approve(<psmAddress>, amt - subsidy)`. Example:

    // Trade DAI + fee for 100 $STABLE
    uint256 WAD = 10 ** 18;
    dai.approve(<psmAddress>, 100 * (psm.tout() + WAD));
    psm.buyGem(address(this), 100 * (10 ** 6));

#### Notes on Fees and Subsidies

When the value of `tin` or `tout` is negative, it means `sellGem` or `buyGem`, respectively, are subsidized by the Maker Protocol.

Please note the fee behaviour is not the same for both functions.

When calling `sellGem()`, Dai is minted at a specific rate (see below)

If you have $STABLE have you call `sellGem()` when fee is 1%, you will receive `Dai - fees` **adjusted by the conversion rate**. In this case the fee is subtracted from the result amount.

If you have $STABLE and the fee is -1%, then you will receive `Dai + subsidy` also **adjusted by the conversion rate**. In this case the subsidy is added to the result amount.

When calling `buyGem()`, you specify the amount of the gem you want to receive.

If you have Dai and you call `buyGem()` when fee is 1%, it's then added on top of the value to determine how much ERC20 Dai you require in your account. So if you call `buyGem()`, you will be required to send `Dai + fees` **adjusted by the conversion rate**.

If you have Dai and the fee is -1%, then you be required to send `Dai - subsidy` **adjusted by the conversion rate**. In this case the subsidy is subtracted from the required amount.

Please note this was a conscious decision to avoid dealing with decimal division and rounding leftovers.

### Note on Conversion Rate

Instead of being pegged 1:1 to `gem`, the ratio is relative to its underlying `asset`. We leverage `ERC4626.convertToAssets()` to get the "oracle price" of the underlying asset in terms of `gem`.

Notice that no `ERC4626.deposit()` or `ERC4626.withdraw()` calls are made. The swaps are made entirely in terms of the yield-bearing token, adjusted by its "price", meaning that the amount of `gem` in the swap might not match exactly the amount of Dai.

## Old Contracts [v1]

### Mainnet

| Contract     | Deployment                                                                                                                 |
| :------      | :-------                                                                                                                   |
| USDC GemJoin | [0x0A59649758aa4d66E25f08Dd01271e891fe52199](https://etherscan.io/address/0x0A59649758aa4d66E25f08Dd01271e891fe52199#code) |
| USDC PSM     | [0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A](https://etherscan.io/address/0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A#code) |
| USDP GemJoin | [0x7bbd8cA5e413bCa521C2c80D8d1908616894Cf21](https://etherscan.io/address/0x7bbd8cA5e413bCa521C2c80D8d1908616894Cf21#code) |
| USDP PSM     | [0x961Ae24a1Ceba861D1FDf723794f6024Dc5485Cf](https://etherscan.io/address/0x961Ae24a1Ceba861D1FDf723794f6024Dc5485Cf#code) |
| GUSD GemJoin | [0xe29A14bcDeA40d83675aa43B72dF07f649738C8b](https://etherscan.io/address/0xe29a14bcdea40d83675aa43b72df07f649738c8b)      |
| GUSD PSM     | [0x204659B2Fd2aD5723975c362Ce2230Fba11d3900](https://etherscan.io/address/0x204659b2fd2ad5723975c362ce2230fba11d3900)      |
