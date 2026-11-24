.PHONY: help status quality test up down e2e e2e-up e2e-down e2e-app-workflow openapi-export openapi-check \
	quality-api quality-assisted quality-caregiver quality-wear-os quality-watchos \
	test-api test-assisted test-caregiver test-wear-os test-watchos

.DEFAULT_GOAL := help

ANDROID_HOME ?= $(HOME)/Library/Android/sdk
BACKEND_BASE_URL ?= http://127.0.0.1:8002

API_DIR := backend/api
PODMAN_RUNTIME_TMPDIR ?= /private/tmp
CONTAINER_COMPOSE ?= $(shell if command -v podman >/dev/null 2>&1; then echo TMPDIR=$(PODMAN_RUNTIME_TMPDIR) podman compose; else echo docker compose; fi)

# Compose command (run from backend/api) used to export the OpenAPI contract.
# Defaults to the local development stack; CI passes the test stack.
API_COMPOSE ?= $(CONTAINER_COMPOSE)
OPENAPI_SNAPSHOT := packages/api_contract/openapi.json

# Isolated test-environment stack for the app workflow E2E: fake push
# provider, no-op rate limiter, plain HTTP published on E2E_PORT.
E2E_PORT ?= 8003
E2E_BASE_URL ?= http://127.0.0.1:$(E2E_PORT)
E2E_COMPOSE ?= $(CONTAINER_COMPOSE) -p fall-guardian-e2e -f compose.test.yaml -f ../../tools/e2e/compose.e2e.yaml

help: ## Show available commands
	@grep -E '(^[a-zA-Z0-9_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

status: ## Show Git status for the monorepo
	git status --short --branch

quality: quality-api quality-assisted quality-caregiver quality-wear-os quality-watchos ## Run all project lint/static quality checks

test: test-api test-assisted test-caregiver test-wear-os test-watchos ## Run every project's automated tests

up: ## Start the local backend development stack (http://127.0.0.1:8002)
	$(MAKE) -C $(API_DIR) up

down: ## Stop the local backend development stack
	$(MAKE) -C $(API_DIR) down

e2e: e2e-up ## Start an isolated test backend, run the app workflow E2E, then stop it
	@status=0; $(MAKE) e2e-app-workflow BACKEND_BASE_URL=$(E2E_BASE_URL) || status=$$?; \
		$(MAKE) e2e-down; exit $$status

e2e-up: ## Start the isolated E2E backend (test env, fake push) and migrate its database
	cd $(API_DIR) && $(E2E_COMPOSE) build
	@# The test stack bind-mounts backend/api; sync vendor/ with composer.lock
	@# (the entrypoint only installs when vendor/ is missing).
	cd $(API_DIR) && $(E2E_COMPOSE) run --rm --no-deps app composer install --no-interaction --no-progress --prefer-dist
	cd $(API_DIR) && $(E2E_COMPOSE) up -d
	@# The entrypoint waits (60s max) for the test-suffixed database, so create
	@# it as soon as the container can run console commands.
	@echo "Creating E2E test database"
	@cd $(API_DIR) && for i in $$(seq 1 60); do \
		$(E2E_COMPOSE) exec -T app php bin/console -e test doctrine:database:create --if-not-exists >/dev/null 2>&1 && exit 0; sleep 3; \
	done; echo "Could not create the E2E test database" >&2; exit 1
	cd $(API_DIR) && $(E2E_COMPOSE) exec -T app php bin/console -e test doctrine:migrations:migrate --no-interaction --allow-no-migration
	@echo "Waiting for $(E2E_BASE_URL)/health"
	@for i in $$(seq 1 60); do curl -fsS -o /dev/null $(E2E_BASE_URL)/health && exit 0; sleep 2; done; \
		echo "E2E backend did not become healthy" >&2; exit 1

e2e-down: ## Stop the isolated E2E backend and drop its volumes
	cd $(API_DIR) && $(E2E_COMPOSE) down -v

e2e-app-workflow: ## Run assisted/caregiver app workflow against BACKEND_BASE_URL (default: local dev backend)
	dart tools/e2e/fall_guardian_workflow_e2e.dart --base-url=$(BACKEND_BASE_URL)

openapi-export: ## Export the API OpenAPI contract to packages/api_contract/openapi.json (backend must be running)
	cd $(API_DIR) && $(API_COMPOSE) exec -T app php bin/console -e test api:openapi:export --output=var/openapi.json
	cp $(API_DIR)/var/openapi.json $(OPENAPI_SNAPSHOT)

openapi-check: openapi-export ## Fail if the committed OpenAPI snapshot differs from the running API
	git diff --exit-code -- $(OPENAPI_SNAPSHOT)

quality-api: ## Run backend API quality checks
	$(MAKE) -C $(API_DIR) quality

quality-assisted: ## Run assisted mobile quality checks
	$(MAKE) -C apps/assisted_mobile quality

quality-caregiver: ## Run caregiver mobile quality checks
	$(MAKE) -C apps/caregiver_mobile quality

quality-wear-os: ## Run Wear OS checks
	ANDROID_HOME=$(ANDROID_HOME) $(MAKE) -C apps/wear_os check

quality-watchos: ## Run watchOS checks
	$(MAKE) -C apps/watchos check

test-api: ## Run backend PHPUnit and Behat suites (backend dev stack must be running)
	$(MAKE) -C $(API_DIR) test
	$(MAKE) -C $(API_DIR) test-behat

test-assisted: ## Run assisted mobile Flutter tests
	$(MAKE) -C apps/assisted_mobile test

test-caregiver: ## Run caregiver mobile Flutter tests
	$(MAKE) -C apps/caregiver_mobile test

test-wear-os: ## Run Wear OS JVM unit tests
	ANDROID_HOME=$(ANDROID_HOME) $(MAKE) -C apps/wear_os test

test-watchos: ## Run watchOS deterministic tests
	$(MAKE) -C apps/watchos test
