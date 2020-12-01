#!/bin/bash

####################################################
# Deploy all scripts on chain to prepare for spell
#
# Requires MCD environment variables to be in scope https://changelog.makerdao.com/releases/kovan/active/contracts.json
####################################################

# Update these to whatever gem is required
ILK=$(seth --to-bytes32 "$(seth --from-ascii "PSM-USDC-A")")
TOKEN=$USDC
PIP=$PIP_USDC
LERP_START=10000000000000000    # 1%
LERP_END=1000000000000000       # 0.1%
LERP_DUR=604800                 # 1 week

# Build everything
dapp --use solc:0.6.7 build

echo "Deploying contracts..."

# Deploy AuthGemJoin5
GEM_JOIN_PSM=$(dapp create AuthGemJoin5 $MCD_VAT $ILK $TOKEN)
sleep 3     # Sleeps are added so the block can propagate

# Deploy the PSM
PSM=$(dapp create DssPsm $GEM_JOIN_PSM $MCD_JOIN_DAI $MCD_VOW)
sleep 3

# Deploy new Flipper
FLIPPER_PSM_NO_CHECK=$(TX=$(seth send $FLIP_FAB 'newFlip(address,address,bytes32)(address)' $MCD_VAT $MCD_CAT $ILK --async) && seth receipt $TX logs | jq -r '.[0].address')
FLIPPER_PSM=$(seth --to-address $FLIPPER_PSM_NO_CHECK)
sleep 3

# Deploy lerp module
LERP=$(dapp create Lerp $PSM $(seth --to-bytes32 "$(seth --from-ascii "tin")") $LERP_START $LERP_END $LERP_DUR)
sleep 3

# Set up permissions
echo "Setting up permissions..."

seth send $GEM_JOIN_PSM 'rely(address)' $MCD_PAUSE_PROXY
sleep 3
seth send $GEM_JOIN_PSM 'rely(address)' $PSM
sleep 3
seth send $GEM_JOIN_PSM 'deny(address)' $ETH_FROM
sleep 3

seth send $FLIPPER_PSM 'rely(address)' $MCD_PAUSE_PROXY
sleep 3
seth send $FLIPPER_PSM 'deny(address)' $ETH_FROM
sleep 3

seth send $PSM 'rely(address)' $MCD_PAUSE_PROXY
sleep 3
seth send $PSM 'rely(address)' $LERP
sleep 3
seth send $PSM 'deny(address)' $ETH_FROM
sleep 3

seth send $LERP 'rely(address)' $MCD_PAUSE_PROXY
sleep 3
seth send $LERP 'deny(address)' $ETH_FROM

echo "GEM_JOIN_PSM=$GEM_JOIN_PSM"
echo "PSM=$PSM"
echo "FLIPPER_PSM=$FLIPPER_PSM"
echo "LERP=$LERP"