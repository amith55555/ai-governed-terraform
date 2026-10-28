.DEFAULT_GOAL := help
DEV_DIR := terraform/envs/dev
.PHONY: help check scan policy plan-policy risk risk-test test plan up down

help: ## List available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

check: scan policy risk-test ## Run all local checks (same as CI)
	@echo "check: all checks passed"

scan: ## Security scan (Checkov plus guards)
	bash scripts/scan.sh

policy: ## Policy unit tests and source-code policy (no AWS needed)
	conftest verify --policy policies/terraform
	conftest verify --policy policies/hcl
	bash scripts/source-policy.sh

plan-policy: ## Policies on a plan JSON: make plan-policy PLAN=path/to/plan.json
	@test -n "$(PLAN)" || { echo "usage: make plan-policy PLAN=path/to/plan.json"; exit 1; }
	conftest test "$(PLAN)" --policy policies/terraform --all-namespaces

risk: ## Risk level of a plan JSON: make risk PLAN=plan.json OUT=risk.json
	@test -n "$(PLAN)" -a -n "$(OUT)" || { echo "usage: make risk PLAN=plan.json OUT=risk.json"; exit 1; }
	python3 risk/risk_gate.py "$(PLAN)" > "$(OUT)"

risk-test: ## Unit tests for the risk gate
	python3 -m unittest discover -s risk -v

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
