#!/usr/bin/env bash
set -e

if [[ -z "$1" ]]; then
  forge test --rpc-url="$ETH_RPC_URL" --use solc:0.8.14
else
  forge test --rpc-url="$ETH_RPC_URL" --use solc:0.8.14 --match "$1" -vvvv
fi
