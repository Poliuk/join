APP = build/Join.app

.PHONY: build app icon run test clean

build:
	swift build -c release --product Join

app:
	scripts/build-app.sh

icon:
	swift scripts/make-icon.swift

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf .build build
