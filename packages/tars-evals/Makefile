.PHONY: help install test lint creds generate-datasets eval-suite eval-rollup eval-check-gate

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

# STEMS= / STEMS_FILE= optional — scope generation *and* pruning to those stems:
#   make generate-datasets STEMS="ongoing_listings supply_retention_sale"
#   make generate-datasets STEMS_FILE=.tars-eval-expected-stems
generate-datasets: ## Regenerate datasets/*.yaml from metric_entities golden queries only
	uv run python scripts/generate_datasets_from_context_docs.py \
	    $(foreach stem,$(STEMS),--stem $(stem)) \
	    $(if $(STEMS_FILE),--stems-file $(STEMS_FILE))

# STEM= optional. Examples:
#   make eval-suite
#   make eval-suite STEM=turnover
eval-suite: ## Per-dataset evals (parallel workers) + rollup. Optional STEM=<stem>.
	scripts/run_dataset_queue.sh $(STEM)

eval-rollup: ## Merge logs/per_dataset/*/summary.json into rollup.json + gate_summary.json
	uv run python scripts/build_rollup.py

eval-check-gate: ## Re-check gate_summary.json without re-running anything; exits non-zero on a failing gate
	uv run python scripts/check_gate.py gate_summary.json
