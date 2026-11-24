.PHONY: help test coverage analyze build check clean

.DEFAULT_GOAL := help

PROJECT := FallGuardian/FallGuardian.xcodeproj
SCHEME := FallGuardian Watch App
DESTINATION ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)
# Line-coverage gate for the host-tested logic files. Set to the achieved
# coverage of the least-covered gated file; raise it, never lower it.
MIN_COVERAGE ?= 93
COVERAGE_FILES := \
	"FallGuardian Watch App/WatchAlertDeadline.swift" \
	"FallGuardian Watch App/FallAlgorithm.swift"

help: ## Show available commands
	@echo "Fall Guardian watchOS app"
	@echo ""
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

test: ## Run XCTest unit tests for the pure alert logic and fall algorithm (macOS host)
	swift test --enable-code-coverage

coverage: test ## Enforce line coverage on the tested logic files
	python3 scripts/check_coverage.py "$$(swift test --show-codecov-path)" $(MIN_COVERAGE) $(COVERAGE_FILES)

analyze: ## Run Xcode static analyzer
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" analyze

build: ## Build the watchOS app on the configured simulator
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(DESTINATION)" build

check: coverage analyze build ## Run deterministic quality checks

clean: ## Clean Xcode and SwiftPM build artifacts
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" clean
	swift package clean
