#!/bin/bash
# Builds Snapwise and prints only errors plus the final status.
cd "$(dirname "$0")"
xcodegen generate >/dev/null
xcodebuild -project Snapwise.xcodeproj -scheme Snapwise -configuration "${1:-Debug}" -derivedDataPath .derived build 2>&1 \
  | grep -E "error|BUILD" | sed "s|$PWD/Sources/Snapwise/||" | sort -u
