.PHONY: help install test lint creds generate-datasets eval-suite eval-rollup eval-check-gate eval-scope drift-check eval-changed inspect-view-s3

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

# View archived Inspect logs directly from S3 (no sync). Opens http://127.0.0.1:7575
# after QLI/ConsoleMe auth. Overrides:
#   make inspect-view-s3 S3_URI=s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-26512/pipeline-89418
#   make inspect-view-s3 ROLE_ARN=arn:aws:iam::ACCOUNT:role/ROLE PORT=7576
#   make inspect-view-s3 USE_AMBIENT=1   # skip QLI; use ambient/Weep credentials
#   make inspect-view-s3 LIST=1         # list child prefixes under S3_URI (or archive root)
inspect-view-s3: ## Start Inspect View against S3 archive (QLI auth → http://127.0.0.1:7575)
	uv run python scripts/view_inspect_logs_s3.py \
	    $(if $(S3_URI),--log-dir $(S3_URI)) \
	    $(if $(ROLE_ARN),--role-arn $(ROLE_ARN)) \
	    $(if $(PORT),--port $(PORT)) \
	    $(if $(USE_AMBIENT),--use-ambient-credentials) \
	    $(if $(LIST),--list)

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

# The three targets below mirror .woodpecker/tars_evals.yml one-for-one, so
# `make eval-changed` answers "will the gate pass on my branch?" before you
# push. BASE=/HEAD= override the diff range (default: merge base with
# origin/master, the same range the PR gate diffs):
#   make eval-scope BASE=HEAD~1
#   DRY_RUN=1 make eval-changed
eval-scope: ## Resolve which dataset stems the current diff affects (no eval)
	@TARS_EVAL_BASE="$(BASE)" TARS_EVAL_HEAD="$(HEAD)" scripts/resolve_eval_scope.sh

drift-check: eval-scope ## Regenerate in-scope datasets; fail if committed YAML differs
	@scripts/check_dataset_drift.sh

eval-changed: eval-scope drift-check ## Local run of the CI gate: eval only the changed stems
	@scripts/eval_changed.sh
