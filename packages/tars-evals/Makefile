.PHONY: help install test lint creds

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Sync the standalone uv project (dev deps included)
	uv sync

test: ## Run unit tests
	uv run pytest tests/ -v

lint: ## Lint with ruff
	uv run ruff check src/ tests/ scripts/

creds: ## Verify the LiteLLM key can be fetched from Vault (via qli)
	@scripts/fetch_litellm_key.sh >/dev/null && echo "OK: LiteLLM key reachable in Vault (apps/forno/litellm/zordon-tars-llm)"
