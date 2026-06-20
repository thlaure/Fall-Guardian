.PHONY: help install format format-check analyze test coverage coverage-check quality check build-android build-ios run-android-debug run-android-wired run-ios-profile logs-flutter logs-android logs-ios-console clean

.DEFAULT_GOAL := help

ADB ?= $(shell if [ -x "$(HOME)/Library/Android/sdk/platform-tools/adb" ]; then echo "$(HOME)/Library/Android/sdk/platform-tools/adb"; else echo adb; fi)
XCRUN ?= xcrun
DEVICE_ID ?=
IOS_DEVICE_ID ?= $(if $(DEVICE_ID),$(DEVICE_ID),iPhone)
IOS_BUNDLE_ID ?= com.fallguardian.caregiverApp
ANDROID_PACKAGE_ID ?= com.fallguardian.caregiver_app
BACKEND_BASE_URL ?=
FIREBASE_ANDROID_API_KEY ?=
FIREBASE_IOS_API_KEY ?=
DEVICE_ARG := $(if $(DEVICE_ID),-d $(DEVICE_ID),)
ANDROID_DEVICE_ARG := $(if $(DEVICE_ID),-s $(DEVICE_ID),)
BACKEND_ARG := $(if $(BACKEND_BASE_URL),--dart-define=BACKEND_BASE_URL=$(BACKEND_BASE_URL),)
FIREBASE_ANDROID_ARG := $(if $(FIREBASE_ANDROID_API_KEY),--dart-define=FIREBASE_ANDROID_API_KEY=$(FIREBASE_ANDROID_API_KEY),)
FIREBASE_IOS_ARG := $(if $(FIREBASE_IOS_API_KEY),--dart-define=FIREBASE_IOS_API_KEY=$(FIREBASE_IOS_API_KEY),)
FIREBASE_ARGS := $(FIREBASE_ANDROID_ARG) $(FIREBASE_IOS_ARG)

help: ## Show available commands
	@echo "Fall Guardian caregiver app"
	@echo ""
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Install Flutter dependencies
	flutter pub get

format: ## Format Dart source and tests
	dart format lib/ test/

format-check: ## Check Dart formatting without modifying files
	dart format --set-exit-if-changed lib/ test/

analyze: ## Run Flutter static analysis
	flutter analyze

test: ## Run Flutter tests
	flutter test

coverage: ## Run Flutter tests with coverage output
	flutter test --coverage

coverage-check: coverage ## Require at least 90% line coverage
	dart run tool/check_lcov.dart coverage/lcov.info 90 lib/l10n/ lib/screens/

quality: format-check analyze coverage-check ## Run deterministic quality checks

check: quality ## Run the default verification set

build-android: ## Build Android debug APK
	flutter build apk --debug $(FIREBASE_ARGS)

build-ios: ## Build iOS simulator app
	flutter build ios --simulator --debug $(FIREBASE_ARGS)

run-android-debug: ## Install and launch Android debug build on a physical device
	flutter run --debug $(DEVICE_ARG) --no-resident $(BACKEND_ARG) $(FIREBASE_ARGS)

run-android-wired: ## Launch Android debug through USB reverse proxy to the local backend
	$(ADB) $(ANDROID_DEVICE_ARG) reverse tcp:8002 tcp:8002
	flutter run --debug $(DEVICE_ARG) --no-resident --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8002 $(FIREBASE_ARGS)
	$(ADB) $(ANDROID_DEVICE_ARG) reverse tcp:8002 tcp:8002

run-ios-profile: ## Install and launch iOS profile build on a physical device
	flutter run --profile $(DEVICE_ARG) --no-resident $(BACKEND_ARG) $(FIREBASE_ARGS)

logs-flutter: ## Stream Flutter logs from the selected running app
	flutter logs $(DEVICE_ARG)

logs-android: ## Stream logs for the running Android app process
	$(ADB) $(ANDROID_DEVICE_ARG) logcat --pid=$$($(ADB) $(ANDROID_DEVICE_ARG) shell pidof $(ANDROID_PACKAGE_ID))

logs-ios-console: ## Relaunch iOS app and attach its console output
	$(XCRUN) devicectl device process launch --device $(IOS_DEVICE_ID) --terminate-existing --console $(IOS_BUNDLE_ID)

clean: ## Clean Flutter build artifacts
	flutter clean
