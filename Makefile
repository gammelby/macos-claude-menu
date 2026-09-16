APP_NAME   := Claude Menu
BUILD_DIR  := .build/release
APP_BUNDLE := build/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications

.PHONY: build test app run install clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp $(BUILD_DIR)/ClaudeMenu "$(APP_BUNDLE)/Contents/MacOS/ClaudeMenu"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --sign - "$(APP_BUNDLE)"

run: app
	pkill -x ClaudeMenu && while pgrep -x ClaudeMenu >/dev/null; do sleep 0.1; done || true
	open "$(APP_BUNDLE)"

install: app
	pkill -x ClaudeMenu && while pgrep -x ClaudeMenu >/dev/null; do sleep 0.1; done || true
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf .build build
