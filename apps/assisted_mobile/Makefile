.PHONY: help install format format-check analyze test coverage coverage-check quality check build-android build-ios run-android-debug run-android-wired run-ios-debug run-ios-profile logs-flutter logs-android logs-ios-console clean

.DEFAULT_GOAL := help

-include .env.local

ADB ?= $(shell if [ -x "$(HOME)/Library/Android/sdk/platform-tools/adb" ]; then echo "$(HOME)/Library/Android/sdk/platform-tools/adb"; else echo adb; fi)
XCRUN ?= xcrun
DEVICE_ID ?=
IOS_DEVICE_ID ?= $(if $(DEVICE_ID),$(DEVICE_ID),iPhone)
BACKEND_BASE_URL ?=
LOCAL_HOSTNAME ?= $(shell scutil --get LocalHostName 2>/dev/null || hostname -s)
IOS_BACKEND_BASE_URL ?= $(if $(BACKEND_BASE_URL),$(BACKEND_BASE_URL),http://$(LOCAL_HOSTNAME).local:8002)
ANDROID_PACKAGE_ID ?= com.fallguardian
IOS_BUNDLE_ID ?= com.fallguardian.app
DEVICE_ARG := $(if $(DEVICE_ID),-d $(DEVICE_ID),)
ANDROID_DEVICE_ARG := $(if $(DEVICE_ID),-s $(DEVICE_ID),)
BACKEND_ARG := $(if $(BACKEND_BASE_URL),--dart-define=BACKEND_BASE_URL=$(BACKEND_BASE_URL),)
IOS_BACKEND_ARG := --dart-define=BACKEND_BASE_URL=$(IOS_BACKEND_BASE_URL)

help: ## Show available commands
	@echo "Fall Guardian assisted app"
	@echo ""
	@grep -h -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

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
	dart run tool/check_lcov.dart coverage/lcov.info 90 lib/l10n/ lib/screens/ lib/services/watch_communication_service.dart lib/services/notification_service.dart lib/services/sms_service.dart lib/services/secure_store.dart lib/services/location_service.dart

quality: format-check analyze coverage-check ## Run deterministic quality checks

check: quality ## Run the default verification set

build-android: ## Build Android debug APK
	flutter build apk --debug

build-ios: ## Build iOS simulator app
	flutter build ios --simulator --debug $(DEVICE_ARG)

run-android-debug: ## Install and launch Android debug build on a physical device
	flutter run --debug $(DEVICE_ARG) --no-resident $(BACKEND_ARG)

run-android-wired: ## Launch Android debug through USB reverse proxy to the local backend
	$(ADB) $(ANDROID_DEVICE_ARG) reverse tcp:8002 tcp:8002
	flutter run --debug $(DEVICE_ARG) --no-resident --dart-define=BACKEND_BASE_URL=http://127.0.0.1:8002
	$(ADB) $(ANDROID_DEVICE_ARG) reverse tcp:8002 tcp:8002

run-ios-debug: ## Install and launch iOS debug build on a physical device
	flutter run --debug $(DEVICE_ARG) --no-resident $(IOS_BACKEND_ARG)

run-ios-profile: ## Install and launch iOS profile build on a physical device
	flutter run --profile $(DEVICE_ARG) --no-resident $(IOS_BACKEND_ARG)

logs-flutter: ## Stream Flutter logs from the selected running app
	flutter logs $(DEVICE_ARG)

logs-android: ## Stream logs for the running Android app process
	$(ADB) $(ANDROID_DEVICE_ARG) logcat --pid=$$($(ADB) $(ANDROID_DEVICE_ARG) shell pidof $(ANDROID_PACKAGE_ID))

logs-ios-console: ## Relaunch iOS app and attach its console output
	$(XCRUN) devicectl device process launch --device $(IOS_DEVICE_ID) --terminate-existing --console $(IOS_BUNDLE_ID)

clean: ## Clean Flutter build artifacts
	flutter clean
