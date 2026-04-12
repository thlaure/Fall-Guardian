.PHONY: help up down build rebuild shell logs logs-app logs-messenger ps composer-install composer-update lint lint-dry analyse rector rector-dry quality grumphp test-unit test-integration test test-behat migrate db-diff db-reset cache-clear routes console messenger-consume worker-failed worker-retry install

.DEFAULT_GOAL := help

GREEN  := \033[0;32m
CYAN   := \033[0;36m
RESET  := \033[0m
DOCKER_COMPOSE := docker compose -f docker-compose.yml

help: ## Show this help
	@echo ""
	@echo "$(CYAN)Fall Guardian Backend$(RESET) - Available commands:"
	@echo ""
	@grep -E '(^[a-zA-Z_-]+:.*?##.*$$)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'
	@echo ""

up: ## Start all containers
	$(DOCKER_COMPOSE) up -d

down: ## Stop all containers
	$(DOCKER_COMPOSE) down

build: ## Build containers
	$(DOCKER_COMPOSE) build

rebuild: ## Rebuild containers from scratch
	$(DOCKER_COMPOSE) down -v
	$(DOCKER_COMPOSE) build --no-cache
	$(DOCKER_COMPOSE) up -d

shell: ## Enter app container shell
	$(DOCKER_COMPOSE) exec app sh

logs: ## Tail all logs
	$(DOCKER_COMPOSE) logs -f

logs-app: ## Tail app logs
	$(DOCKER_COMPOSE) logs -f app

logs-messenger: ## Tail messenger logs
	$(DOCKER_COMPOSE) logs -f messenger

ps: ## List running containers
	$(DOCKER_COMPOSE) ps

composer-install: ## Install composer dependencies
	$(DOCKER_COMPOSE) exec app composer install

composer-update: ## Update composer dependencies
	$(DOCKER_COMPOSE) exec app composer update

lint: ## Run PHP CS Fixer
	$(DOCKER_COMPOSE) exec app vendor/bin/php-cs-fixer fix --diff --verbose

lint-dry: ## Run PHP CS Fixer in dry-run mode
	$(DOCKER_COMPOSE) exec app vendor/bin/php-cs-fixer fix --diff --verbose --dry-run

analyse: ## Run PHPStan
	$(DOCKER_COMPOSE) exec app vendor/bin/phpstan analyse

rector: ## Run Rector
	$(DOCKER_COMPOSE) exec app vendor/bin/rector process

rector-dry: ## Run Rector in dry-run mode
	$(DOCKER_COMPOSE) exec app vendor/bin/rector process --dry-run

quality: lint-dry analyse rector-dry ## Run all quality tools

grumphp: ## Run GrumPHP
	$(DOCKER_COMPOSE) exec app vendor/bin/grumphp run

test-unit: ## Run unit tests
	$(DOCKER_COMPOSE) exec app vendor/bin/phpunit --testsuite=Unit

test-integration: ## Run integration tests
	$(DOCKER_COMPOSE) exec app vendor/bin/phpunit --testsuite=Integration

test: ## Run all PHPUnit tests
	$(DOCKER_COMPOSE) exec app vendor/bin/phpunit

test-behat: ## Run Behat API tests
	$(DOCKER_COMPOSE) exec app vendor/bin/behat --config behat.yaml.dist --colors

migrate: ## Run database migrations
	$(DOCKER_COMPOSE) exec app php bin/console doctrine:migrations:migrate --no-interaction

db-diff: ## Generate a Doctrine migration
	$(DOCKER_COMPOSE) exec app php bin/console doctrine:migrations:diff

db-reset: ## Reset database
	$(DOCKER_COMPOSE) exec app php bin/console doctrine:database:drop --force --if-exists
	$(DOCKER_COMPOSE) exec app php bin/console doctrine:database:create
	$(DOCKER_COMPOSE) exec app php bin/console doctrine:migrations:migrate --no-interaction

cache-clear: ## Clear Symfony cache
	$(DOCKER_COMPOSE) exec app php bin/console cache:clear

routes: ## List routes
	$(DOCKER_COMPOSE) exec app php bin/console debug:router

console: ## Run arbitrary Symfony console command (usage: make console CMD="cache:clear")
	$(DOCKER_COMPOSE) exec app php bin/console $(CMD)

messenger-consume: ## Start messenger worker in foreground
	$(DOCKER_COMPOSE) exec app php bin/console messenger:consume async -vv

worker-failed: ## Show failed messenger messages
	$(DOCKER_COMPOSE) exec app php bin/console messenger:failed:show

worker-retry: ## Retry failed messages
	$(DOCKER_COMPOSE) exec app php bin/console messenger:failed:retry

install: build up composer-install migrate ## Full backend setup
	@echo "$(GREEN)Fall Guardian backend is ready$(RESET)"
	@echo "API docs: $(CYAN)http://localhost:8002/docs$(RESET)"
	@echo "Device API: $(CYAN)http://localhost:8002/api/v1$(RESET)"
