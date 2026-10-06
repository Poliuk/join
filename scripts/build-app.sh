#!/bin/sh
# Builds Join.app from the Swift package. Only the Command Line Tools are required.
#   CONFIG=debug scripts/build-app.sh          # debug build
#   ARCHS="arm64 x86_64" scripts/build-app.sh  # universal build, as releases are
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-$(uname -m)}"
APP="build/Join.app"

# One build per architecture, joined into a single binary. The architectures share one cached
# build manifest, and SwiftPM 5.10 fails a rebuild that reuses another architecture's, so it's
# planned afresh each time.
set --
for ARCH in $ARCHS; do
    swift build -c "$CONFIG" --product Join --arch "$ARCH" --disable-build-manifest-caching
    set -- "$@" "$(swift build -c "$CONFIG" --product Join --arch "$ARCH" --show-bin-path)/Join"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$@" -output "$APP/Contents/MacOS/Join"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc signature with an explicit designated requirement. A plain ad-hoc signature identifies
# the app by the hash of this exact build, so macOS forgets the calendar permission after every
# rebuild. Pinning the requirement to the bundle identifier keeps the grant across rebuilds.
codesign --force --sign - --requirements '=designated => identifier "com.poliuk.join"' "$APP"

echo "Built $APP"
