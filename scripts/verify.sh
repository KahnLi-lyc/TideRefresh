#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
action="${1:-test}"
destination="${2:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
xcodebuild -project Examples/TideRefreshDemo.xcodeproj \
  -scheme TideRefreshDemo -destination "$destination" \
  -derivedDataPath .build/DerivedData "$action" CODE_SIGNING_ALLOWED=NO
