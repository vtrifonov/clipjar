CONFIG ?= release
VERSION ?= 0.1.0
BUILD_NUMBER ?= 1
ARCHS ?= --arch arm64 --arch x86_64
INSTALL_DIR ?= /Applications
APP = build/Clipjar.app
ZIP = build/Clipjar.zip
BIN_DIR = $(shell swift build -c $(CONFIG) $(ARCHS) --show-bin-path)

.PHONY: build test app sign zip install clean

build:
	swift build -c $(CONFIG) $(ARCHS)

test:
	swift test

# Assembles the bundle by hand; SwiftPM's resource bundles go in Contents/Resources.
app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN_DIR)/Clipjar" "$(APP)/Contents/MacOS/Clipjar"
	cp -R "$(BIN_DIR)"/*.bundle "$(APP)/Contents/Resources/"
	test -d "$(APP)/Contents/Resources/KeyboardShortcuts_KeyboardShortcuts.bundle"
	cp LICENSE THIRD_PARTY_NOTICES.md "$(APP)/Contents/Resources/"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(APP)/Contents/Info.plist"
	@archs="$$(lipo -archs "$(APP)/Contents/MacOS/Clipjar")"; echo "$$archs"; case " $$archs " in *" arm64 "*) ;; *) echo "missing arm64" >&2; exit 1 ;; esac; case " $$archs " in *" x86_64 "*) ;; *) echo "missing x86_64" >&2; exit 1 ;; esac

# Ad-hoc signature: not notarized.
sign: app
	codesign --force --deep -s - "$(APP)"
	codesign --verify --deep --strict "$(APP)"

zip: sign
	rm -f "$(ZIP)"
	ditto -c -k --keepParent "$(APP)" "$(ZIP)"

# Refuses an empty or missing INSTALL_DIR, so the rm below can only ever remove <INSTALL_DIR>/Clipjar.app.
install: sign
	@test -n "$(INSTALL_DIR)" || { echo "INSTALL_DIR is empty" >&2; exit 1; }
	@test -d "$(INSTALL_DIR)" || { echo "INSTALL_DIR does not exist: $(INSTALL_DIR)" >&2; exit 1; }
	pkill -x Clipjar || true
	rm -rf "$(INSTALL_DIR)/Clipjar.app"
	ditto "$(APP)" "$(INSTALL_DIR)/Clipjar.app"

clean:
	rm -rf .build build
