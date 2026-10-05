APP = build/Join.app

.PHONY: build app run test clean

build:
	swift build -c release --product Join

app:
	scripts/build-app.sh

run: app
	open $(APP)

test:
	swift test

clean:
	rm -rf .build build
