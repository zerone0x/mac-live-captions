# Same commands locally and in CI (.github/workflows/ci.yml).

PROJECT  := LiveCaptions.xcodeproj
SCHEME   := LiveCaptions
CONFIG   ?= Release
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/$(CONFIG)/LiveCaptions.app
ZIP      := build/LiveCaptions.zip
SHOTS    := build/screenshots

.PHONY: all generate test test-core test-speech build package verify screenshots check-offline open clean

all: check-offline test build

## Generate LiveCaptions.xcodeproj from project.yml (needs `brew install xcodegen`).
generate:
	xcodegen generate

## Run all package tests (Swift Testing).
test: test-core test-speech

## Core logic tests: pure Swift, no hardware.
test-core:
	swift test --package-path Packages/Core

## Speech adapter tests. The real-audio test needs `say` and the en-US speech
## model; it skips with a printed reason when they are missing
## (LIVECAPTIONS_SKIP_REAL_AUDIO=1 skips it on purpose).
test-speech:
	swift test --package-path Packages/SpeechAdapter

## Build the ad-hoc signed app into build/DerivedData.
build: generate
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-destination 'generic/platform=macOS' \
		-derivedDataPath $(DERIVED) \
		build

## Zip the built app (keeps symlinks and signature intact).
package: build verify
	rm -f $(ZIP)
	ditto -c -k --sequesterRsrc --keepParent $(APP) $(ZIP)
	@echo "Packaged $(ZIP)"

## Sanity-check the built bundle: menu-bar only, usage strings, arm64, signature
## with hardened runtime and exactly the expected entitlements, stripped binary.
verify:
	scripts/verify-app.sh $(APP)

## Render overlay screenshots (PNG) with the built app; CI uploads them.
screenshots:
	rm -rf $(SHOTS)
	$(APP)/Contents/MacOS/LiveCaptions --render-overlay-snapshots $(SHOTS)

## Fail if networking APIs appear in the caption path (see docs/DECISIONS.md).
check-offline:
	scripts/check-offline.sh

open: generate
	open $(PROJECT)

clean:
	rm -rf build $(PROJECT)
