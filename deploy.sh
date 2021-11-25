#!/bin/bash

####################################################
# Deploy all scripts on chain to prepare for spell
#
# Requires MCD environment variables to be in scope https://changelog.makerdao.com/releases/kovan/active/contracts.json
#
# Usage: ./deploy.sh <ILK> <GEM JOIN VARIANT> <TOKEN ADDRESS> <PIP ADDRESS>
# Example: ./deploy.sh PSM-USDC-A AuthGemJoin5 $USDC $PIP_USDC
####################################################

# Update these to whatever gem is required
ILK=$(seth --to-bytes32 "$(seth --from-ascii "$1")")
GEMJOIN=$2
TOKEN=$3
PIP=$4

# Build everything
dapp --use solc:0.6.12 build

echo "Deploying contracts..."

# Deploy Gem Join
GEM_JOIN_PSM=$(dapp create $GEMJOIN $MCD_VAT $ILK $TOKEN)
sleep 3     # Sleeps are added so the block can propagate

# Deploy the PSM
PSM=$(dapp create DssPsm $GEM_JOIN_PSM $MCD_JOIN_DAI $MCD_VOW)
sleep 3

# Deploy new Clipper
CLIPPER_PSM_NO_CHECK=$(TX=$(seth send $CLIP_FAB 'newClip(address,address,address,address,bytes32)(address)' $MCD_PAUSE_PROXY $MCD_VAT $MCD_SPOT $MCD_DOG $ILK --async) && seth receipt $TX logs | jq -r '.[0].address')
CLIPPER_PSM=$(seth --to-address $CLIPPER_PSM_NO_CHECK)
sleep 3

# Deploy new Clip Calc
CLIPPER_CALC_NO_CHECK=$(TX=$(seth send $CALC_FAB 'newStairstepExponentialDecrease(address)(address)' $MCD_PAUSE_PROXY --async) && seth receipt $TX logs | jq -r '.[0].address')
CLIPPER_CALC=$(seth --to-address $CLIPPER_CALC_NO_CHECK)
sleep 3

# Set up permissions
echo "Setting up permissions..."

seth send $GEM_JOIN_PSM 'rely(address)' $MCD_PAUSE_PROXY
sleep 3
seth send $GEM_JOIN_PSM 'rely(address)' $PSM
sleep 3
seth send $GEM_JOIN_PSM 'deny(address)' $ETH_FROM
sleep 3

seth send $PSM 'rely(address)' $MCD_PAUSE_PROXY
sleep 3
seth send $PSM 'deny(address)' $ETH_FROM
sleep 3

echo "GEM_JOIN=$GEM_JOIN_PSM"
echo "PSM=$PSM"
echo "CLIPPER=$CLIPPER_PSM"
echo "CLIPPER_CALC=$CLIPPER_CALC"
