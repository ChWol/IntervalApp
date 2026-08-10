#!/usr/bin/env bash
# Run the IntervalApp regression suite the same way coding agents should.
set -euo pipefail
cd "$(dirname "$0")/.."

# A half-written xctest bundle from an interrupted build makes xctest refuse to load it.
rm -rf .build/Build/Products/Debug/IntervalAppTests.xctest

xcodebuild \
  -project IntervalApp.xcodeproj \
  -scheme IntervalApp \
  -destination 'platform=macOS' \
  -derivedDataPath .build \
  test \
  -only-testing:IntervalAppTests \
  "$@"
