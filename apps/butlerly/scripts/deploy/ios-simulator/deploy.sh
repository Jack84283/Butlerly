#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
SIMULATOR_ID=${1:-booted}

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is required but was not found." >&2
  exit 1
}
command -v xcrun >/dev/null 2>&1 || {
  echo "Xcode command-line tools are required." >&2
  exit 1
}

echo "Building Butlerly for the iOS Simulator..."
cd "$APP_DIR"
flutter build ios --simulator

echo "Installing Butlerly on simulator '$SIMULATOR_ID'..."
xcrun simctl install "$SIMULATOR_ID" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$SIMULATOR_ID" com.butlerly.butlerly
