.PHONY: help status quality test quality-api quality-assisted quality-caregiver quality-wear-os quality-watchos

.DEFAULT_GOAL := help

help: ## Show available commands
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

status: ## Show Git status for the monorepo
	git status --short --branch

quality: quality-api quality-assisted quality-caregiver quality-wear-os quality-watchos ## Run all project quality checks

test: quality ## Alias for the full deterministic verification set

quality-api: ## Run backend API quality checks
	$(MAKE) -C backend/api quality

quality-assisted: ## Run assisted mobile quality checks
	$(MAKE) -C apps/assisted_mobile quality

quality-caregiver: ## Run caregiver mobile quality checks
	$(MAKE) -C apps/caregiver_mobile quality

quality-wear-os: ## Run Wear OS checks
	$(MAKE) -C apps/wear_os check

quality-watchos: ## Run watchOS checks
	$(MAKE) -C apps/watchos check

