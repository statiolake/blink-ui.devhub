#!/bin/sh
# Run the headless tests: $NVIM (Neovim 0.11 or later), devhub.nvim from
# $DEVHUB_NVIM (default: a checkout beside this one).
set -eu
cd "$(dirname "$0")/.."
NVIM="${NVIM:-nvim}"
DEVHUB_NVIM="${DEVHUB_NVIM:-../devhub.nvim}"
"$NVIM" --headless --clean --cmd "set rtp^=$PWD" --cmd "set rtp^=$DEVHUB_NVIM" -l tests/spec.lua
