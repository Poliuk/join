#!/bin/sh
# Builds Join.app from the Swift package. Only the Command Line Tools are required.
#   CONFIG=debug scripts/build-app.sh   # debug build
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Join.app"

swift build -c "$CONFIG" --product Join
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Join" "$APP/Contents/MacOS/Join"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature: enough for TCC (calendar permission) to recognise the bundle.
codesign --force --sign - "$APP"

echo "Built $APP"
