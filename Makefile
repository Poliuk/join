APP = build/Join.app

.PHONY: build app icon release run test clean

build:
	swift build -c release --product Join

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
	swift test

clean:
	rm -rf .build build
