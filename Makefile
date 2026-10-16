# Sail — build without an Xcode project.
#   make            build + assemble build/Sail.app (ad-hoc signed)
#   make test       unit tests
#   make run        build and launch the bundle (logs in Console / `make log`)
#   make install    copy to /Applications and install the root helper (asks for sudo)
#   make uninstall  remove app, helper, login item
APP        := Sail
BUNDLE_ID  := com.jiraffekiller.sail
HELPER     := com.jiraffekiller.sail.helper
AGENT      := com.jiraffekiller.sail.agent
CONF       := release
BIN        := .build/$(CONF)
OUT        := build/$(APP).app
CONTENTS   := $(OUT)/Contents

.PHONY: all build bundle test run install install-app install-helper uninstall clean log status icon dmg

all: bundle

build:
	swift build -c $(CONF)

test:
	swift test

bundle: build
	rm -rf "$(OUT)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources" "$(CONTENTS)/Library/LaunchAgents"
	cp "$(BIN)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	cp "$(BIN)/SailHelper" "$(CONTENTS)/MacOS/SailHelper"
	cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	cp Resources/$(HELPER).plist Resources/AppIcon.icns scripts/install-helper.sh scripts/uninstall-helper.sh "$(CONTENTS)/Resources/"
	cp Resources/$(AGENT).plist "$(CONTENTS)/Library/LaunchAgents/"
	codesign --force -s - --identifier $(HELPER) "$(CONTENTS)/MacOS/SailHelper"
	codesign --force -s - --identifier $(BUNDLE_ID) "$(OUT)"
	@echo "built $(OUT)"

run: bundle
	open "$(OUT)"

status:
	"$(CONTENTS)/MacOS/$(APP)" --status

install: bundle
	-pkill -x $(APP) 2>/dev/null
	rm -rf "/Applications/$(APP).app"
	cp -R "$(OUT)" /Applications/
	$(MAKE) install-helper
	"/Applications/$(APP).app/Contents/MacOS/$(APP)" --login-item on

# Re-deploy only the app (no sudo); the running copy is replaced via the LaunchAgent if enabled.
install-app: bundle
	-pkill -x $(APP) 2>/dev/null
	rm -rf "/Applications/$(APP).app"
	cp -R "$(OUT)" /Applications/
	@if "/Applications/$(APP).app/Contents/MacOS/$(APP)" --login-item status | grep -q enabled; then \
		launchctl kickstart gui/$$(id -u)/$(AGENT) || open "/Applications/$(APP).app"; else open "/Applications/$(APP).app"; fi

install-helper:
	sudo sh scripts/install-helper.sh "Resources/$(HELPER).plist" "$(BIN)/SailHelper"

uninstall:
	-pkill -x $(APP) 2>/dev/null
	-"/Applications/$(APP).app/Contents/MacOS/$(APP)" --login-item off 2>/dev/null
	-launchctl bootout gui/$$(id -u)/$(AGENT) 2>/dev/null
	rm -f "$$HOME/Library/LaunchAgents/$(AGENT).plist"
	sudo sh scripts/uninstall-helper.sh
	rm -rf "/Applications/$(APP).app"

log:
	/usr/bin/log stream --style compact --predicate 'subsystem == "$(BUNDLE_ID)"'

# Disk image with the usual "drag to Applications" window. Needs `brew install create-dmg`.
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
DMG     := build/$(APP)-v$(VERSION).dmg
dmg: bundle
	rm -rf build/dmg-src "$(DMG)"
	mkdir -p build/dmg-src && cp -R "$(OUT)" build/dmg-src/
	create-dmg --volname "$(APP)" --volicon Resources/AppIcon.icns \
		--background Resources/dmg-background.png --window-pos 200 120 --window-size 660 400 \
		--icon-size 128 --text-size 14 --icon "$(APP).app" 165 190 --hide-extension "$(APP).app" \
		--app-drop-link 495 190 --no-internet-enable "$(DMG)" build/dmg-src/
	@echo "built $(DMG)"

# Regenerate Resources/AppIcon.icns from scripts/make-icon.swift.
icon:
	swift scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf .build build
