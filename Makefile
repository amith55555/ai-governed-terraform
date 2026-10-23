.DEFAULT_GOAL := help
.PHONY: help check test plan up down

help: ## List available targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-7s %s\n", $$1, $$2}'

check: ## Run all local checks (same as CI)
	@echo "check: not implemented yet"

test: ## Run tests
	@echo "test: not implemented yet"

plan: ## Terraform plan (dev)
	@echo "plan: not implemented yet"

up: ## Create the dev environment
	@echo "up: not implemented yet"

down: ## Destroy the dev environment
	@echo "down: not implemented yet"
