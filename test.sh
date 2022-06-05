#!/usr/bin/env bash
set -e

if [[ -z "$1" ]]; then
  forge test
else
  forge test --match "$1" -vvvv
fi
