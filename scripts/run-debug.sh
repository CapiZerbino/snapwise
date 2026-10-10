#!/bin/bash
# Builds and launches the Debug app (includes the debug automation URL commands). Use ./run.sh for the real app.
set -euo pipefail
cd "$(dirname "$0")/.."
status=$(./build.sh Debug)
echo "$status"
[[ "$status" == *"BUILD SUCCEEDED"* ]] || exit 1
pkill -x Snapwise 2>/dev/null && sleep 1 || true
open .derived/Build/Products/Debug/Snapwise.app
