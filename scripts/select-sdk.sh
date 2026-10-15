# Sourced by scripts/build-app.sh and the Makefile before they run SwiftPM: picks the macOS SDK and
# exports it as SDKROOT, which swift build and swift test read.
#   - SDKROOT already set: used as it is.
#   - Xcode: its default SDK.
#   - The Command Line Tools alone: their default SDK, unless it makes SwiftUI's @State a macro, as the
#     macOS 27 SDK does. Only Xcode ships the plugin that expands it (SwiftUIMacros), so the newest
#     macOS 26 SDK the tools have builds the app instead.
if [ -z "${SDKROOT:-}" ]; then
    join_developer="$(xcode-select -p)"
    join_sdk="$(xcrun --sdk macosx --show-sdk-path)"
    if [ ! -e "$join_developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ] &&
        grep -qs 'type: "StateMacro"' "$join_sdk"/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/*.swiftinterface; then
        SDKROOT="$(ls -d "$join_developer"/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -n 1)"
        if [ -z "$SDKROOT" ]; then
            echo "error: the macOS $(xcrun --sdk macosx --show-sdk-version) SDK needs Xcode's SwiftUI macros, and $join_developer has no macOS 26 SDK; install Xcode or set SDKROOT" >&2
            exit 1
        fi
        export SDKROOT
        echo "Building with $(basename "$SDKROOT"): the Command Line Tools can't expand SwiftUI's macros in their macOS $(xcrun --sdk macosx --show-sdk-version) SDK"
    fi
    unset join_developer join_sdk
fi
