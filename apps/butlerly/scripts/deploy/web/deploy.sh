#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
PORT=${1:-8080}

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is required but was not found." >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "Python 3 is required to run the local web server." >&2
  exit 1
}

echo "Building Butlerly for the web..."
cd "$APP_DIR"
flutter build web --release

echo "Serving Butlerly at http://localhost:$PORT"
echo "Other devices on this Wi-Fi can use http://<this-mac-ip>:$PORT"
echo "Press Control-C to stop."
cd build/web
python3 -m http.server "$PORT" --bind 0.0.0.0
