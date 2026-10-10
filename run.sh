#!/bin/bash
# Builds the Release app, places it next to this script as Snapwise.app and launches it.
set -euo pipefail
cd "$(dirname "$0")"
status=$(./build.sh Release)
echo "$status"
[[ "$status" == *"BUILD SUCCEEDED"* ]] || exit 1
pkill -x Snapwise 2>/dev/null && sleep 1 || true
rm -rf Snapwise.app
cp -R .derived/Build/Products/Release/Snapwise.app Snapwise.app
codesign --verify --deep --strict Snapwise.app
# Xcode registers its build products with LaunchServices; left alone, `snapwise://` links and hotkeys can end up
# in one of those stale copies instead of this app.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
find . \( -name Snapwise.app -o -name Lumshot.app \) -path "*Products*" -maxdepth 6 -exec "$lsregister" -u "$PWD/{}" \; >/dev/null 2>&1 || true
pkill -x Lumshot 2>/dev/null || true # the app's former name
"$lsregister" -f "$PWD/Snapwise.app" >/dev/null 2>&1 || true
open Snapwise.app
