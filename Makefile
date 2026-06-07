.PHONY: help up down build rebuild shell logs logs-app logs-messenger ps composer-install composer-update lint lint-dry analyse rector rector-dry security-check quality grumphp test-db test-unit test-integration test test-behat coverage-text coverage-html migrate db-diff db-reset cache-clear routes console messenger-consume worker-failed worker-retry install

.DEFAULT_GOAL := help

GREEN  := \033[0;32m
CYAN   := \033[0;36m
RESET  := \033[0m
COMPOSE ?= $(shell if command -v podman >/dev/null 2>&1; then echo podman compose; else echo docker compose; fi)

help: ## Show this help
	@echo ""
	@echo "$(CYAN)Fall Guardian Backend$(RESET) - Available commands:"
	@echo ""
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

up: ## Start all containers
	$(COMPOSE) up -d

down: ## Stop all containers
	$(COMPOSE) down

build: ## Build containers
	$(COMPOSE) build

rebuild: ## Rebuild containers from scratch
	$(COMPOSE) down -v
	$(COMPOSE) build --no-cache
	$(COMPOSE) up -d

shell: ## Enter app container shell
	$(COMPOSE) exec app sh

logs: ## Tail all logs
	$(COMPOSE) logs -f

logs-app: ## Tail app logs
	$(COMPOSE) logs -f app

logs-messenger: ## Tail messenger logs
	$(COMPOSE) logs -f messenger

ps: ## List running containers
	$(COMPOSE) ps

composer-install: ## Install composer dependencies
	$(COMPOSE) exec app composer install

composer-update: ## Update composer dependencies
	$(COMPOSE) exec app composer update

lint: ## Run PHP CS Fixer
	$(COMPOSE) exec app vendor/bin/php-cs-fixer fix --diff --verbose

lint-dry: ## Run PHP CS Fixer in dry-run mode
	$(COMPOSE) exec app vendor/bin/php-cs-fixer fix --diff --verbose --dry-run

analyse: ## Run PHPStan
	$(COMPOSE) exec app vendor/bin/phpstan analyse

rector: ## Run Rector
	$(COMPOSE) exec app vendor/bin/rector process

rector-dry: ## Run Rector in dry-run mode
	$(COMPOSE) exec app vendor/bin/rector process --dry-run

security-check: ## Check Composer dependencies for known vulnerabilities
	$(COMPOSE) exec app vendor/bin/security-checker security:check composer.lock

quality: lint-dry analyse rector-dry security-check ## Run deterministic quality tools

grumphp: ## Run GrumPHP
	$(COMPOSE) exec app vendor/bin/grumphp run

test-db: ## Recreate the test database schema
	$(COMPOSE) exec app php bin/console doctrine:database:create --env=test --if-not-exists
	$(COMPOSE) exec app php bin/console doctrine:schema:drop --env=test --force --full-database
	$(COMPOSE) exec app php bin/console doctrine:schema:create --env=test

test-unit: ## Run unit tests
	$(COMPOSE) exec app vendor/bin/phpunit --testsuite=unit

test-integration: test-db ## Run integration tests
	$(COMPOSE) exec app vendor/bin/phpunit --testsuite=integration

test: test-db ## Run all PHPUnit tests
	$(COMPOSE) exec app vendor/bin/phpunit --coverage-text

coverage-html: ## Generate HTML coverage report (var/reports/phpunit-coverage/index.html)
	$(COMPOSE) exec app vendor/bin/phpunit --no-results --coverage-html var/reports/phpunit-coverage
	@echo ""
	@echo "Report: var/reports/phpunit-coverage/index.html"

test-behat: ## Run Behat API tests
	$(COMPOSE) exec app vendor/bin/behat --config behat.yaml.dist --colors

migrate: ## Run database migrations
	$(COMPOSE) exec app php bin/console doctrine:migrations:migrate --no-interaction

db-diff: ## Generate a Doctrine migration
	$(COMPOSE) exec app php bin/console doctrine:migrations:diff

db-reset: ## Reset database
	$(COMPOSE) exec app php bin/console doctrine:database:drop --force --if-exists
	$(COMPOSE) exec app php bin/console doctrine:database:create
	$(COMPOSE) exec app php bin/console doctrine:migrations:migrate --no-interaction

cache-clear: ## Clear Symfony cache
	$(COMPOSE) exec app php bin/console cache:clear

routes: ## List routes
	$(COMPOSE) exec app php bin/console debug:router

console: ## Run arbitrary Symfony console command (usage: make console CMD="cache:clear")
	$(COMPOSE) exec app php bin/console $(CMD)

messenger-consume: ## Start messenger worker in foreground
	$(COMPOSE) exec app php bin/console messenger:consume async -vv

worker-failed: ## Show failed messenger messages
	$(COMPOSE) exec app php bin/console messenger:failed:show

worker-retry: ## Retry failed messages
	$(COMPOSE) exec app php bin/console messenger:failed:retry

install: build up composer-install migrate ## Full backend setup
	@echo "$(GREEN)Fall Guardian backend is ready$(RESET)"
	@echo "API docs: $(CYAN)http://localhost:8002/docs$(RESET)"
	@echo "Device API: $(CYAN)http://localhost:8002/api/v1$(RESET)"
