.PHONY: help install format format-check analyze test coverage coverage-check quality check build-android build-ios run-ios-profile logs-flutter logs-ios-console clean

.DEFAULT_GOAL := help

XCRUN ?= xcrun
DEVICE_ID ?=
IOS_DEVICE_ID ?= $(if $(DEVICE_ID),$(DEVICE_ID),iPhone)
IOS_BUNDLE_ID ?= com.fallguardian.caregiverApp
BACKEND_BASE_URL ?=
DEVICE_ARG := $(if $(DEVICE_ID),-d $(DEVICE_ID),)
BACKEND_ARG := $(if $(BACKEND_BASE_URL),--dart-define=BACKEND_BASE_URL=$(BACKEND_BASE_URL),)

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
	flutter build apk --debug

build-ios: ## Build iOS simulator app
	flutter build ios --simulator --debug

run-ios-profile: ## Install and launch iOS profile build on a physical device
	flutter run --profile $(DEVICE_ARG) --no-resident $(BACKEND_ARG)

logs-flutter: ## Stream Flutter logs from the selected running app
	flutter logs $(DEVICE_ARG)

logs-ios-console: ## Relaunch iOS app and attach its console output
	$(XCRUN) devicectl device process launch --device $(IOS_DEVICE_ID) --terminate-existing --console $(IOS_BUNDLE_ID)

clean: ## Clean Flutter build artifacts
	flutter clean
