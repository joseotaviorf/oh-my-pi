# DataHub business context (curated Data Products)

This folder holds the **MD-driven pipeline** that publishes curated **Data Products** into [DataHub](https://github.com/acryldata/datahub): product copy, dataset links, glossary terms, golden SQL (Query entities), sidebar structured properties, and a documentation link.

**Source of truth:** `docs/llm_context/business_entities/*.md` only. Entity YAML is generated ephemerally in CI (never committed).

Consumers such as **TARS** use the **DataHub MCP** against the published catalog without cloning this repo.

---

## End-to-end flow

```
docs/llm_context/business_entities/{entity}.md
        ↓  CI: generate_and_push_datahub_entities.py (LiteLLM)
   ephemeral *.datahub.yaml (temp dir)
        ↓  load_collections_context.py
      DataHub
```

**Woodpecker** (`.woodpecker/datahub.yml`):

| Step | When | Action |
|------|------|--------|
| `generate-and-push-datahub` | push to CICD branch / master / hotfix | MD → YAML → push (changed MDs; all MDs if loader changed) |
| `validate-datahub-entities-push` | push (after generate) | smoke test: changed MDs have a live Data Product |
| `validate-datahub-entities-pr` | pull request | smoke test: full catalog |

---

## Layout

| Path | Role |
|------|------|
| [`reference/`](./reference/) | LLM schema examples (`_TEMPLATE`, `payments`, `visits`) |
| [`datahub_domain_catalog.py`](./datahub_domain_catalog.py) | Fetch live DataHub domains for LLM inference + validation |
| [`load_collections_context.py`](./load_collections_context.py) | GraphQL loader (consumes YAML from `--config`) |
| [`smoke_test_datahub.py`](./smoke_test_datahub.py) | Read-only: Data Product exists per entity MD filename |
| [`push_all_entities.py`](./push_all_entities.py) | **Deprecated** — forwards to `generate_and_push_datahub_entities.py --all` |
| [`packages/.../generate_and_push_datahub_entities.py`](../../packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py) | CI entry point: MD → ephemeral YAML → push |

---

## Authoring a new entity

1. Create `docs/llm_context/business_entities/{entity_slug}.md` from [`_TEMPLATE.md`](../../docs/llm_context/business_entities/_TEMPLATE.md).
2. Merge to master (or push to the CICD branch) — CI generates YAML and publishes to DataHub.
3. Verify: `python dags/governance/datahub_business_context/smoke_test_datahub.py`

`data_product_id` is derived from the MD filename: `accounting_funnel.md` → `accounting-funnel`.

`golden_query.stable_urn` is assigned deterministically (`uuid5(entity_slug)`) by CI — no manual UUID management.

---

## Local commands

```bash
export DATAHUB_GRAPHQL_URL="https://datahub-gms.apps.data-prd.habitat.zone/api/graphql"
export DATAHUB_TOKEN="<token>"
export OPENAI_API_KEY="<litellm-proxy-key>"

# Push one entity (generates ephemeral YAML + publishes)
uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py \
  docs/llm_context/business_entities/payments.md

# Push all entities (LLM cost — full refresh)
uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py --all

# Smoke test (read-only — no LLM)
python dags/governance/datahub_business_context/smoke_test_datahub.py --verbose

# Loader only (debug with reference example)
python dags/governance/datahub_business_context/load_collections_context.py \
  --config dags/governance/datahub_business_context/reference/payments.datahub.yaml
```

---

## Related tooling

[`benchmark_report.md`](benchmark_report.md) and eval scripts are benchmarking utilities — not required for day-to-day publication.
