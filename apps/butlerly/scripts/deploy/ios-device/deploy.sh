#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
DEVICE_ID=${1:-}

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is required but was not found." >&2
  exit 1
}

if [ -z "$DEVICE_ID" ]; then
  echo "Connected Flutter devices:"
  flutter devices
  echo
  echo "Usage: $0 <physical-iphone-device-id>" >&2
  echo "Configure Signing & Capabilities in ios/Runner.xcodeproj first." >&2
  exit 2
fi

echo "Building, signing, and installing Butlerly on $DEVICE_ID..."
cd "$APP_DIR"
flutter run --release -d "$DEVICE_ID"
