#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is required but was not found." >&2
  exit 1
}

echo "Building Butlerly for macOS..."
cd "$APP_DIR"
flutter build macos --release

APP_PATH="$APP_DIR/build/macos/Build/Products/Release/butlerly.app"
[ -d "$APP_PATH" ] || {
  echo "Build completed but butlerly.app was not found." >&2
  exit 1
}

echo "Launching Butlerly from: $APP_PATH"
open "$APP_PATH"
echo "To keep it installed, drag butlerly.app into Applications."
