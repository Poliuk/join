#!/bin/sh
# Builds Join.app from the Swift package, with Xcode or with only the Command Line Tools.
#   CONFIG=debug scripts/build-app.sh          # debug build
#   ARCHS="arm64 x86_64" scripts/build-app.sh  # universal build, as releases are
#   SDKROOT=/path/to/MacOSX.sdk scripts/build-app.sh  # another SDK (see scripts/select-sdk.sh)
set -eu
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
ARCHS="${ARCHS:-$(uname -m)}"
APP="build/Join.app"

. scripts/select-sdk.sh

# One build per architecture, joined into a single binary. The binary records the SDK it was built with, as
# Xcode and SwiftPM's native build system (CI's) record it: Swift Build, SwiftPM's default from 6.4, records
# the deployment target instead, and AppKit decides some behaviour by that version, so a local build would
# differ from the release. Passing the version to the linker records it the same way everywhere (it's the
# value the native build system passes anyway). The native build system once failed a rebuild that reused
# another architecture's cached build manifest, so the build is planned afresh each time; each binary is
# copied out as soon as it's built, since Swift Build puts every architecture's at the same path.
MINIMUM="$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)"
BUILD="-Xlinker -platform_version -Xlinker macos -Xlinker $MINIMUM -Xlinker $(xcrun --show-sdk-version)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
set --
for ARCH in $ARCHS; do
    swift build -c "$CONFIG" --product Join --arch "$ARCH" $BUILD --disable-build-manifest-caching
    cp "$(swift build -c "$CONFIG" --product Join --arch "$ARCH" $BUILD --show-bin-path)/Join" "$STAGE/Join-$ARCH"
    set -- "$@" "$STAGE/Join-$ARCH"
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
