#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Building IntervalApp (macOS)..."
xcodebuild -scheme IntervalApp \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/dd_iv_mac \
  build > /dev/null

echo "==> Installing into /Applications/IntervalApp.app..."
rm -rf /Applications/IntervalApp.app
cp -R /tmp/dd_iv_mac/Build/Products/Debug/IntervalApp.app /Applications/

echo "==> Registering with LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Applications/IntervalApp.app

echo "✅ Successfully installed latest IntervalApp into /Applications!"
