#!/usr/bin/env bash
set -e

if [[ -z "$1" ]]; then
  dapp --use solc:0.6.12 test
else
  dapp --use solc:0.6.12 test --match "$1" -vv
fi
