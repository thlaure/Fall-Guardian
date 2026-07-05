.PHONY: help status quality test e2e-app-workflow quality-api quality-assisted quality-caregiver quality-wear-os quality-watchos

.DEFAULT_GOAL := help

ANDROID_HOME ?= $(HOME)/Library/Android/sdk
BACKEND_BASE_URL ?= http://127.0.0.1:8002

help: ## Show available commands
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

status: ## Show Git status for the monorepo
	git status --short --branch

quality: quality-api quality-assisted quality-caregiver quality-wear-os quality-watchos ## Run all project quality checks

test: quality ## Alias for the full deterministic verification set

e2e-app-workflow: ## Run assisted/caregiver app workflow against the local backend API
	dart tools/e2e/fall_guardian_workflow_e2e.dart --base-url=$(BACKEND_BASE_URL)

quality-api: ## Run backend API quality checks
	$(MAKE) -C backend/api quality

quality-assisted: ## Run assisted mobile quality checks
	$(MAKE) -C apps/assisted_mobile quality

quality-caregiver: ## Run caregiver mobile quality checks
	$(MAKE) -C apps/caregiver_mobile quality

quality-wear-os: ## Run Wear OS checks
	ANDROID_HOME=$(ANDROID_HOME) $(MAKE) -C apps/wear_os check

quality-watchos: ## Run watchOS checks
	$(MAKE) -C apps/watchos check
