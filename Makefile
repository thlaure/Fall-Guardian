FLUTTER_APP_DIR := flutter_app
IOS_DEVICE      := 5A2143B9-4E6E-43F6-A6DA-7A74734C9E69
WATCH_DEVICE    := 4167470A-88C3-489C-A4FB-7AA9F695E2CB
ADB             := $(HOME)/Library/Android/sdk/platform-tools/adb
# Detect ADB serials by model name so boot order doesn't matter.
ANDROID_DEVICE  := $(shell $(ADB) devices -l 2>/dev/null | grep sdk_gphone | awk '{print $$1}')
WEAR_DEVICE     := $(shell $(ADB) devices -l 2>/dev/null | grep sdk_gwear  | awk '{print $$1}')
WATCHOS_PROJECT    := watchos_app/FallGuardian/FallGuardian.xcodeproj
WATCHOS_SCHEME     := FallGuardian Watch App
WATCHOS_BUNDLE_ID  := com.fallguardian.app.watchkitapp
WATCHOS_BUILD_DIR  := /tmp/fall_guardian_watch_build
WEAR_APP_DIR    := wear_os_app

.PHONY: help install run run-ios run-android run-android-debug run-watchos run-wear sim-boot check test test-e2e test-e2e-ios test-e2e-android test-e2e-all analyze format clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  check         Format + test + analyze (run before every commit)"
	@echo "  sim-boot      Boot iOS and watchOS simulators"
	@echo "  install       Install Flutter dependencies"
	@echo "  run-ios       Boot pair, build watchOS, run Flutter on iPhone 17"
	@echo "  run-android-debug Build/install/launch Android phone app without attaching flutter run"
	@echo "  run-watchos   Build and run watchOS app on simulator"
	@echo "  run-android   Run on Android emulator"
	@echo "  test-e2e      Run iOS/watchOS end-to-end tests (legacy alias)"
	@echo "  test-e2e-ios  Run iOS/watchOS end-to-end tests"
	@echo "  test-e2e-android Run Android/Wear OS end-to-end tests"
	@echo "  test-e2e-all  Run both mobile end-to-end suites"
	@echo "  run-wear      Build and install Wear OS app on emulator"
	@echo "  test          Run all unit and widget tests"
	@echo "  analyze       Run static analysis"
	@echo "  format        Auto-format Dart code"
	@echo "  clean         Clean build artifacts"

check: ## Run before every commit: auto-format Dart, run all unit/widget tests, then static analysis
	cd $(FLUTTER_APP_DIR) && dart format lib/ test/ && flutter test && flutter analyze

sim-boot: ## Boot the iPhone 17 and Apple Watch simulators and open the Simulator app
	xcrun simctl boot $(IOS_DEVICE) 2>/dev/null || true
	xcrun simctl boot $(WATCH_DEVICE) 2>/dev/null || true
	open -a Simulator

run-watchos: ## Build the watchOS app with xcodebuild, install it on the watch simulator, and launch it
	xcodebuild \
	  -project "$(WATCHOS_PROJECT)" \
	  -target "$(WATCHOS_SCHEME)" \
	  -sdk watchsimulator26.4 \
	  -arch arm64 \
	  -configuration Debug \
	  CONFIGURATION_BUILD_DIR="$(WATCHOS_BUILD_DIR)" \
	  build
	xcrun simctl install $(WATCH_DEVICE) \
	  "$(WATCHOS_BUILD_DIR)/$(WATCHOS_SCHEME).app"
	xcrun simctl launch $(WATCH_DEVICE) $(WATCHOS_BUNDLE_ID)

run-wear: ## Build Wear OS APK with Gradle, push it to the Wear emulator, and launch MainActivity
	cd $(WEAR_APP_DIR) && ./gradlew assembleDebug
	$(ADB) -s $(WEAR_DEVICE) install -r $(WEAR_APP_DIR)/app/build/outputs/apk/debug/app-debug.apk
	$(ADB) -s $(WEAR_DEVICE) shell am start -n com.fallguardian/.MainActivity

install: ## Install Flutter pub dependencies
	cd $(FLUTTER_APP_DIR) && flutter pub get

run-ios: sim-boot run-watchos ## Boot simulators, build watchOS, then build and launch the Flutter iPhone app
	xcrun simctl terminate $(WATCH_DEVICE) $(WATCHOS_BUNDLE_ID) 2>/dev/null || true  # kill stale watch process
	xcrun simctl terminate $(IOS_DEVICE) com.fallguardian.app 2>/dev/null || true    # kill stale phone process
	xcrun simctl uninstall $(IOS_DEVICE) com.fallguardian.app 2>/dev/null || true    # remove old build to avoid stale state
	sleep 2  # give simctl time to finish uninstalling before re-installing
	cd $(FLUTTER_APP_DIR) && flutter build ios --simulator --debug -d $(IOS_DEVICE)
	xcrun simctl install $(IOS_DEVICE) $(FLUTTER_APP_DIR)/build/ios/iphonesimulator/Runner.app
	xcrun simctl launch $(IOS_DEVICE) com.fallguardian.app

run-android: ## Run the Flutter app on the Android phone emulator (auto-detected by model name)
	cd $(FLUTTER_APP_DIR) && flutter run -d $(ANDROID_DEVICE)

run-android-debug: ## Build the Android debug APK, install it on the phone emulator, and launch MainActivity
	cd $(FLUTTER_APP_DIR) && flutter build apk --debug
	$(ADB) -s $(ANDROID_DEVICE) install -r $(FLUTTER_APP_DIR)/build/app/outputs/flutter-apk/app-debug.apk
	$(ADB) -s $(ANDROID_DEVICE) shell am start -n com.fallguardian/.MainActivity

test: ## Run all Flutter unit and widget tests
	cd $(FLUTTER_APP_DIR) && flutter test

analyze: ## Run Dart static analysis (dart analyze)
	cd $(FLUTTER_APP_DIR) && flutter analyze

format: ## Auto-format all Dart files under lib/ and test/
	cd $(FLUTTER_APP_DIR) && dart format lib/ test/

test-e2e: test-e2e-ios ## Run the iOS/watchOS end-to-end test script (legacy alias)

test-e2e-ios: ## Run the iOS/watchOS end-to-end test script (simulators must already be running)
	./scripts/test_e2e_ios.sh

test-e2e-android: ## Run the Android/Wear OS end-to-end test script (emulators must already be running)
	./scripts/test_e2e_android.sh

test-e2e-all: ## Run both iOS/watchOS and Android/Wear OS end-to-end suites
	./scripts/test_e2e_ios.sh
	./scripts/test_e2e_android.sh

clean: ## Delete Flutter build artifacts (forces a full rebuild next run)
	cd $(FLUTTER_APP_DIR) && flutter clean
