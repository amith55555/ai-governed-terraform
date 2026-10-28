.DEFAULT_GOAL := help
DEV_DIR := terraform/envs/dev
.PHONY: help check test plan up down

help: ## List available targets
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-7s %s\n", $$1, $$2}'

check: scan ## Run all local checks (same as CI)
	@echo "check: all checks passed"

scan: ## Security scan (Checkov plus guards)
	bash scripts/scan.sh

test: ## Run tests
	@echo "test: not implemented yet"

plan: ## Terraform plan (dev)
	terraform -chdir=$(DEV_DIR) init -input=false
	terraform -chdir=$(DEV_DIR) plan

up: ## Create or update the dev environment
	terraform -chdir=$(DEV_DIR) init -input=false
	terraform -chdir=$(DEV_DIR) apply
	@echo "API endpoint: $$(terraform -chdir=$(DEV_DIR) output -raw api_endpoint)"

down: ## Destroy the dev environment
	terraform -chdir=$(DEV_DIR) init -input=false
	terraform -chdir=$(DEV_DIR) destroy
