PROJECT := Docket.xcodeproj
SCHEME := Docket
KIT := Packages/DocketKit
BUILD_DIR := build
CONFIG ?= Debug
BUILD_NUMBER ?= 1
SIGN_IDENTITY ?= Docket Self-Signed Code Signing
APP = $(BUILD_DIR)/Build/Products/$(CONFIG)/Docket.app
SWIFT_SOURCES := $(wildcard App scripts $(KIT)/Sources $(KIT)/Tests $(KIT)/Package.swift)

.PHONY: bootstrap gen build sign test lint format install ci clean

bootstrap:
	brew bundle --file=../../Brewfile

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) -destination 'platform=macOS' \
		CODE_SIGN_IDENTITY=- CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) build

test:
	swift test --package-path $(KIT)

lint:
	swift format lint --strict --recursive $(SWIFT_SOURCES)
	swiftlint lint --strict --quiet

format:
	swift format --in-place --recursive $(SWIFT_SOURCES)
	swiftlint lint --fix --quiet

sign:
	SIGN_IDENTITY="$(SIGN_IDENTITY)" scripts/codesign-app.sh "$(APP)"

install:
	$(MAKE) build sign CONFIG=Release
	-osascript -e 'quit app "Docket"'
	rm -rf /Applications/Docket.app
	ditto "$(BUILD_DIR)/Build/Products/Release/Docket.app" /Applications/Docket.app
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Docket.app
	open /Applications/Docket.app

ci:
	../../scripts/ci.sh

clean:
	rm -rf $(BUILD_DIR) $(PROJECT) $(KIT)/.build
