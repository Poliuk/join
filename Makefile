APP = build/Join.app
# Picks the macOS SDK for SwiftPM (scripts/select-sdk.sh): SDKROOT when set, else one that builds with
# the developer tools in use.
SELECT_SDK = . scripts/select-sdk.sh &&

.PHONY: build app icon release run test clean

build:
	$(SELECT_SDK) swift build -c release --product Join

app:
	scripts/build-app.sh

icon:
	swift scripts/make-icon.swift

# make release VERSION=1.1.0 — see docs/RELEASING.md
release:
	scripts/release.sh $(VERSION)

run: app
	open $(APP)

# Swift Build in Swift 6.4 sometimes leaves Swift Testing's macro plugin off a test file's compile command
# ("plugin for module 'TestingMacros' not found"), so name the toolchain's folder for it when it has one.
TESTING_PLUGINS = "$$(dirname "$$(xcrun -f swift)")/../lib/swift/host/plugins/testing"

test:
	$(SELECT_SDK) plugins=$(TESTING_PLUGINS) && if [ -d "$$plugins" ]; then swift test -Xswiftc -plugin-path -Xswiftc "$$plugins"; else swift test; fi

clean:
	rm -rf .build build
