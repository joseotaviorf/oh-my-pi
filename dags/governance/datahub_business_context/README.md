# DataHub business context (curated Data Products)

This folder holds the **MD-driven pipeline** that publishes curated **Data Products** into [DataHub](https://github.com/acryldata/datahub): product copy, dataset links, glossary terms, golden SQL (Query entities), sidebar structured properties, and a documentation link.

**Source of truth:** `docs/llm_context/{business,metric}_entities/*.md` in git. Entity YAML is generated ephemerally in CI (never committed).

Consumers such as **TARS** use the **DataHub MCP** against the published catalog without cloning this repo.

---

## End-to-end flow

```
docs/llm_context/{business,metric}_entities/{entity}.md
        ↓  PR validation (offline template contract)
        ↓  merge to master / hotfix
        ↓  CI: generate_and_push_datahub_entities.py (LiteLLM)
   ephemeral *.datahub.yaml (temp dir)
        ↓  load_collections_context.py
      DataHub
```

**Contribution paths:**

| Path | Who | Entry |
|------|-----|-------|
| **Luigi (Zordon)** | Business users via Google Chat | Upload `.md` → PR `luigi/data-product/*` → merge |
| **Engineer-authored** | Data engineers | PR with `docs/llm_context/**` changes |

The DataHub UI Context Document flow (`tars-entity` tag → sync → PR) has been **retired**. All new and updated entity docs must go through git.

**Woodpecker** (`.woodpecker/datahub.yml`):

| Step | When | Action |
|------|------|--------|
| `validate-datahub-context-entities` | pull request | Offline template contract (sections, placeholders) |
| `validate-entity-golden-queries-metadata` | push to master / hotfix | Golden-query Trino SQL syntax + tables/columns vs repo `dags/**/metadata` YAML |
| `push-datahub-business-context` | push to master / hotfix | MD → YAML → push (changed MDs only) |
| `validate-datahub-entities-post-push` | push (after generate) | smoke test: changed MDs have a live Data Product |
| `validate-datahub-entities` | pull request | smoke test: changed MDs |

### DataHub fallback for the golden-query schema gate

`validate-entity-golden-queries-metadata` normally requires every `schema.table` referenced by a
golden query to have a metadata YAML under `dags/**/metadata`. Tables such as `sandbox.*`
(Luigi Jr / ad-hoc materializations) may exist only in DataHub.

`datahub_table_fallback.py` closes that gap: when a table is missing from repo metadata, the
gate probes DataHub (read-only GraphQL — dataset existence + `schemaMetadata.fields`) before
failing. A table found only in DataHub passes column checks against the DataHub schema
silently; a table absent from both stays a blocking error.

The probe is a no-op unless both `DATAHUB_GRAPHQL_URL` and `DATAHUB_TOKEN` are set. CI wires
the same read-only secrets already used by `validate-datahub-entities`. Pass
`--no-datahub-fallback` to force repo-metadata-only behavior locally.

---

## Luigi PR feedback (Zordon)

When `validate-datahub-context-entities` runs on a `luigi/data-product/*` PR, validation results
are posted as a single upserted GitHub comment (`sync/pr_comment.py`, marker
`<!-- luigi-ci-validation -->`). Zordon's review poller relays that comment back to the user's
Google Chat thread.

---

## Layout

| Path | Role |
|------|------|
| [`reference/`](./reference/) | LLM schema examples (`_TEMPLATE`, `payments`, `visits`) |
| [`datahub_domain_catalog.py`](./datahub_domain_catalog.py) | Fetch live DataHub domains for LLM inference + validation |
| [`datahub_table_fallback.py`](./datahub_table_fallback.py) | Golden-query gate: DataHub existence/schema probe for tables missing repo metadata YAML |
| [`load_collections_context.py`](./load_collections_context.py) | GraphQL loader (consumes YAML from `--config`) |
| [`smoke_test_datahub.py`](./smoke_test_datahub.py) | Read-only: Data Product exists per entity MD filename |
| [`push_all_entities.py`](./push_all_entities.py) | **Deprecated** — forwards to `generate_and_push_datahub_entities.py --all` |
| [`validate_datahub_context_entities.py`](./validate_datahub_context_entities.py) | Offline PR gate for entity Markdown |
| [`sync/`](./sync/) | Shared Markdown parser, sanitizer, and Luigi PR comment helper |
| [`packages/.../generate_and_push_datahub_entities.py`](../../packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py) | CI entry point: MD → ephemeral YAML → push |

---

## Authoring a new entity

1. Create `docs/llm_context/business_entities/{entity_slug}.md` from [`_TEMPLATE.md`](../../docs/llm_context/business_entities/_TEMPLATE.md).
2. Open a PR — CI validates the template contract.
3. Merge to master (or push to hotfix) — CI generates YAML and publishes to DataHub.
4. Verify: `python dags/governance/datahub_business_context/smoke_test_datahub.py`

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

# Offline template validation (no DataHub/LLM credentials)
make validate-datahub-context-entities

# Golden-query schema gate (Trino syntax + tables/columns vs repo metadata; no execution).
uv run --project packages/bietlejuice-compiler python \
  dags/governance/datahub_business_context/validate_entity_golden_queries_metadata.py \
  --paths docs/llm_context/business_entities/payments.md

# Loader only (debug with reference example)
python dags/governance/datahub_business_context/load_collections_context.py \
  --config dags/governance/datahub_business_context/reference/payments.datahub.yaml
```

---

## Related tooling

[`benchmark_report.md`](benchmark_report.md) and eval scripts are benchmarking utilities — not required for day-to-day publication.
