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

test:
	$(SELECT_SDK) swift test

clean:
	rm -rf .build build
