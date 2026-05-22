#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release/Maya AI Studio.app"
BIN="$APP/Contents/MacOS/Maya AI Studio"

xcodebuild \
  -project "$ROOT/Maya.xcodeproj" \
  -scheme Maya \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build >/tmp/maya-performance-build.log

swift "$ROOT/scripts/check-timeline-drag-regression.swift"
MAYA_SKIP_HEADLESS_VIDEO_BENCHMARK=1 "$BIN" --maya-performance-benchmark
