FLUTTER_APP_DIR := flutter_app
IOS_DEVICE      := EDE46410-BD1D-4BE5-9036-55233A8C8029
WATCH_DEVICE    := A43EFB00-5FBD-45DC-85EA-DF910AEEF014
ANDROID_DEVICE  := emulator-5554
WEAR_DEVICE     := emulator-5556
ADB             := $(HOME)/Library/Android/sdk/platform-tools/adb
WATCHOS_PROJECT    := watchos_app/FallGuardian/FallGuardian.xcodeproj
WATCHOS_SCHEME     := FallGuardian Watch App
WATCHOS_BUNDLE_ID  := com.fallguardian.FallGuardian.watchkitapp
WATCHOS_BUILD_DIR  := /tmp/fall_guardian_watch_build
WEAR_APP_DIR    := wear_os_app

.PHONY: help install run run-ios run-android run-watchos run-wear sim-boot test analyze format clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  sim-boot      Boot iOS and watchOS simulators"
	@echo "  install       Install Flutter dependencies"
	@echo "  run-ios       Run on iOS simulator"
	@echo "  run-watchos   Build and run watchOS app on simulator"
	@echo "  run-android   Run on Android emulator"
	@echo "  run-wear      Build and install Wear OS app on emulator"
	@echo "  test          Run all unit and widget tests"
	@echo "  analyze       Run static analysis"
	@echo "  format        Auto-format Dart code"
	@echo "  clean         Clean build artifacts"

sim-boot:
	xcrun simctl boot $(IOS_DEVICE) 2>/dev/null || true
	xcrun simctl boot $(WATCH_DEVICE) 2>/dev/null || true
	open -a Simulator

run-watchos:
	xcodebuild \
	  -project "$(WATCHOS_PROJECT)" \
	  -scheme "$(WATCHOS_SCHEME)" \
	  -destination "platform=watchOS Simulator,id=$(WATCH_DEVICE)" \
	  -configuration Debug \
	  -derivedDataPath "$(WATCHOS_BUILD_DIR)" \
	  build
	xcrun simctl install $(WATCH_DEVICE) \
	  "$(WATCHOS_BUILD_DIR)/Build/Products/Debug-watchsimulator/$(WATCHOS_SCHEME).app"
	xcrun simctl launch $(WATCH_DEVICE) $(WATCHOS_BUNDLE_ID)

run-wear:
	cd $(WEAR_APP_DIR) && ./gradlew assembleDebug
	$(ADB) -s $(WEAR_DEVICE) install -r $(WEAR_APP_DIR)/app/build/outputs/apk/debug/app-debug.apk
	$(ADB) -s $(WEAR_DEVICE) shell am start -n com.fallguardian/.MainActivity

install:
	cd $(FLUTTER_APP_DIR) && flutter pub get

run-ios:
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
