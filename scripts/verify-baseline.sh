#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tide_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun swift --version
xcrun swift build --triple arm64-apple-ios16.0 --sdk "$tide_sdk" \
  --scratch-path .build/baseline
tide_build="$(xcrun swift build --triple arm64-apple-ios16.0 --sdk "$tide_sdk" \
  --scratch-path .build/baseline --show-bin-path)"
# Compile the complete demo to object code; stable CI separately links and runs it.
xcrun swiftc -swift-version 6 -target arm64-apple-ios16.0 -sdk "$tide_sdk" \
  -I "$tide_build/Modules" \
  -module-name TideRefreshDemo -parse-as-library -whole-module-optimization \
  -emit-object -o .build/baseline/TideRefreshDemo.o Examples/TideRefreshDemo/*.swift
