# Day-to-day commands. `make` alone sets everything up.

SIMULATOR ?= iPhone 18 Pro Max
IPAD ?= iPad Pro 13-inch (M5)
WATCH ?= Apple Watch Series 12 (46mm)
DERIVED = build/dd
APP = $(DERIVED)/Build/Products/Debug-iphonesimulator/POKYH.app
BUNDLE_ID = $(shell sed -n 's/^POKYH_BUNDLE_ID = //p' Config/Base.xcconfig)
XCODEBUILD = xcodebuild -project POKYH.xcodeproj -derivedDataPath $(DERIVED) -quiet

.PHONY: setup project open build build-ipad build-watch test run clean uitest uitest-tsan uitest-asan

# The UI tests against the stub server. DEVICE takes a simulator id, ONLY narrows them down
# (ONLY=BadDataTests/testHugeValues), OUT is where the logs and sanitizer reports land.
DEVICE ?= platform=iOS Simulator,name=$(SIMULATOR)
ONLY ?= POKYHUITests
OUT ?= build/uitest
UITEST = TEST_RUNNER_POKYH_UITEST_DIR="$(abspath $(OUT))" TEST_RUNNER_POKYH_MAIN_THREAD_CHECK=1 \
	xcodebuild test -project POKYH.xcodeproj -scheme POKYH -destination '$(DEVICE)' -derivedDataPath $(DERIVED) \
	-parallel-testing-enabled NO -only-testing:$(if $(findstring POKYHUITests,$(ONLY)),$(ONLY),POKYHUITests/$(ONLY))

setup: Config/Secrets.xcconfig Config/Local.xcconfig project

# First run: copy the templates. Fill them in before building against the real backend.
Config/%.xcconfig:
	cp Config/$*.example.xcconfig $@
	@echo "Created $@ - fill it in."

project:
	@command -v xcodegen >/dev/null || { echo "Needs XcodeGen: brew install xcodegen"; exit 1; }
	xcodegen generate --quiet

open: project
	open POKYH.xcodeproj

build: project
	$(XCODEBUILD) -scheme POKYH -destination 'platform=iOS Simulator,name=$(SIMULATOR)' build

build-ipad: project
	$(XCODEBUILD) -scheme POKYH -destination 'platform=iOS Simulator,name=$(IPAD)' build

build-watch: project
	$(XCODEBUILD) -scheme POKYHWatch -destination 'platform=watchOS Simulator,name=$(WATCH)' build

test:
	cd Packages/PokyhKit && swift test

uitest:
	mkdir -p $(OUT)
	$(UITEST) -resultBundlePath $(OUT)/plain-$$(date +%s).xcresult

uitest-tsan:
	mkdir -p $(OUT)
	$(UITEST) -enableThreadSanitizer YES -resultBundlePath $(OUT)/tsan-$$(date +%s).xcresult

uitest-asan:
	mkdir -p $(OUT)
	$(UITEST) -enableAddressSanitizer YES -enableUndefinedBehaviorSanitizer YES -resultBundlePath $(OUT)/asan-$$(date +%s).xcresult

run: build
	xcrun simctl boot '$(SIMULATOR)' 2>/dev/null || true
	@open -a Simulator 2>/dev/null || true  # newer Xcodes show the simulator inside Xcode instead
	xcrun simctl install '$(SIMULATOR)' $(APP)
	xcrun simctl launch '$(SIMULATOR)' $(BUNDLE_ID)

clean:
	rm -rf $(DERIVED)
