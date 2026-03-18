FLUTTER_APP_DIR := flutter_app
IOS_DEVICE      := 6FC4E816-335D-4DA6-B169-283100CFA0B0
ANDROID_DEVICE  := emulator-5554

.PHONY: help install run run-ios run-android test analyze format clean

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  install       Install Flutter dependencies"
	@echo "  run-ios       Run on iOS simulator"
	@echo "  run-android   Run on Android emulator"
	@echo "  test          Run all unit and widget tests"
	@echo "  analyze       Run static analysis"
	@echo "  format        Auto-format Dart code"
	@echo "  clean         Clean build artifacts"

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
