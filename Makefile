FLUTTER_APP_DIR := flutter_app
IOS_DEVICE      := 5A2143B9-4E6E-43F6-A6DA-7A74734C9E69
WATCH_DEVICE    := 4167470A-88C3-489C-A4FB-7AA9F695E2CB
ANDROID_DEVICE  := emulator-5554
WEAR_DEVICE     := emulator-5556
ADB             := $(HOME)/Library/Android/sdk/platform-tools/adb
WATCHOS_PROJECT    := watchos_app/FallGuardian/FallGuardian.xcodeproj
WATCHOS_SCHEME     := FallGuardian Watch App
WATCHOS_BUNDLE_ID  := com.fallguardian.app.watchkitapp
WATCHOS_BUILD_DIR  := /tmp/fall_guardian_watch_build
WEAR_APP_DIR    := wear_os_app

.PHONY: help install run run-ios run-android run-watchos run-wear sim-boot check test analyze format clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  check         Format + test + analyze (run before every commit)"
	@echo "  sim-boot      Boot iOS and watchOS simulators"
	@echo "  install       Install Flutter dependencies"
	@echo "  run-ios       Boot pair, build watchOS, run Flutter on iPhone 17"
	@echo "  run-watchos   Build and run watchOS app on simulator"
	@echo "  run-android   Run on Android emulator"
	@echo "  run-wear      Build and install Wear OS app on emulator"
	@echo "  test          Run all unit and widget tests"
	@echo "  analyze       Run static analysis"
	@echo "  format        Auto-format Dart code"
	@echo "  clean         Clean build artifacts"

check:
	cd $(FLUTTER_APP_DIR) && dart format lib/ test/ && flutter test && flutter analyze

sim-boot:
	xcrun simctl boot $(IOS_DEVICE) 2>/dev/null || true
	xcrun simctl boot $(WATCH_DEVICE) 2>/dev/null || true
	open -a Simulator

run-watchos:
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

run-wear:
	cd $(WEAR_APP_DIR) && ./gradlew assembleDebug
	$(ADB) -s $(WEAR_DEVICE) install -r $(WEAR_APP_DIR)/app/build/outputs/apk/debug/app-debug.apk
	$(ADB) -s $(WEAR_DEVICE) shell am start -n com.fallguardian/.MainActivity

install:
	cd $(FLUTTER_APP_DIR) && flutter pub get

run-ios: sim-boot run-watchos
	xcrun simctl terminate $(WATCH_DEVICE) $(WATCHOS_BUNDLE_ID) 2>/dev/null || true
	xcrun simctl terminate $(IOS_DEVICE) com.fallguardian.app 2>/dev/null || true
	xcrun simctl uninstall $(IOS_DEVICE) com.fallguardian.app 2>/dev/null || true
	sleep 2
	cd $(FLUTTER_APP_DIR) && flutter run -d $(IOS_DEVICE)

run-android:
	cd $(FLUTTER_APP_DIR) && flutter run -d $(ANDROID_DEVICE)

test:
	cd $(FLUTTER_APP_DIR) && flutter test

analyze:
	cd $(FLUTTER_APP_DIR) && flutter analyze

format:
	cd $(FLUTTER_APP_DIR) && dart format lib/ test/

clean:
	cd $(FLUTTER_APP_DIR) && flutter clean
