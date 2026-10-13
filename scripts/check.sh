#!/usr/bin/env bash
# Runs every check: format, lint, unit tests, rojo build.
set -euo pipefail
cd "$(dirname "$0")/.."
stylua --check src tests
selene src tests
lune run tests/run
mkdir -p build
rojo build -o build/LIDAR.rbxl
echo "All checks passed"
