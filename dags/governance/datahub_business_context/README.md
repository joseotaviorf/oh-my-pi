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
| `validate-datahub-context-entities` | pull request | Offline template contract (sections, placeholders) |
| `validate-entity-golden-queries-metadata` | pull request / push | Golden-query Trino SQL syntax + tables/columns vs repo `dags/**/metadata` YAML |
| `push-datahub-business-context` | push to master / hotfix | MD → YAML → push (changed MDs; all MDs if loader changed) |
| `validate-datahub-entities-post-push` | push (after generate) | smoke test: changed MDs have a live Data Product |
| `validate-datahub-entities` | pull request | smoke test: full catalog |
| `sync-tars-entities` | push (sync path changes) | Context Documents tagged `tars-entity` → Data Product (direct mode) |
| `push-context-documents` | push (context doc changes) | Publish guide + template Markdown as DataHub Context Documents |

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

## Self-service authoring (DataHub Context Documents)

Business users without GitHub access can contribute TARS entity context via **DataHub Context Documents**:

```
DataHub document (tag: tars-entity)  →  sync pipeline  →  Data Product  →  TARS
```

| Path | Role |
|------|------|
| [`context_documents/TARS_ENTITY_TEMPLATE.md`](./context_documents/TARS_ENTITY_TEMPLATE.md) | Git source of truth for the template; auto-synced to [DataHub](https://datahub.apps.data-prd.habitat.zone/document/urn:li:document:tars-entity-template) |
| [`context_documents/AUTHORING_GUIDE.md`](./context_documents/AUTHORING_GUIDE.md) | Git source of truth for the guide; auto-synced to [DataHub](https://datahub.apps.data-prd.habitat.zone/document/urn:li:document:tars-entity-authoring-guide) |
| [`context_documents/context_documents_registry.yml`](./context_documents/context_documents_registry.yml) | Registry mapping Markdown files to stable DataHub document IDs |
| [`push_context_documents.py`](./push_context_documents.py) | Pushes registry Markdown files to DataHub (idempotent; stable URNs) |
| [`policies/tars_entity_metadata_policies.yml`](./policies/tars_entity_metadata_policies.yml) | Access-control policy definitions (import in DataHub UI) |
| [`register_tars_document_structured_properties.py`](./register_tars_document_structured_properties.py) | One-time registration of document sidebar properties |
| [`sync_tars_entities.py`](./sync_tars_entities.py) | Sync orchestrator (gitops or direct mode) |
| [`sync/`](./sync/) | Parser, YAML generator, GitHub PR and direct delivery modules |
| [`../sync_tars_entities/sync_tars_entities_dag.py`](../sync_tars_entities/sync_tars_entities_dag.py) | Hand-written Airflow DAG (PythonOperator; polls every 5 min) |

**Stable DataHub URNs (auto-maintained by CI):**

- Authoring Guide: `urn:li:document:tars-entity-authoring-guide`
- Template: `urn:li:document:tars-entity-template`

### One-time setup (Data Governance admin)

```bash
# 1. Register structured properties on DOCUMENT entities
export DATAHUB_GRAPHQL_URL=...
export DATAHUB_TOKEN=...
make register-datahub-context-props

# 2. Create tag `tars-entity` and import policies from policies/tars_entity_metadata_policies.yml

# 3. Push guide + template to DataHub (or let CI do it on merge to master)
uv run python dags/governance/datahub_business_context/push_context_documents.py
```

### Airflow Variables required for the DAG

| Variable | Required | Description |
|---|---|---|
| `DATAHUB_GRAPHQL_URL` | yes | DataHub GMS GraphQL endpoint |
| `DATAHUB_TOKEN` | yes | Editor-role personal access token |
| `GITHUB_TOKEN` | yes | GitHub PAT with `repo` write scope (for PR creation) |
| `TARS_SYNC_STATE_PATH` | recommended | Path to a **shared, persistent directory** visible to all Airflow workers (e.g. `/mnt/shared/tars-sync/`). The DAG writes `.tars_entity_sync_state.json` there and uses it to skip unchanged documents on the next run. Without this variable the state file lives on the local worker disk and is lost on pod restart, falling back to the GitHub content-equality guard. |

### Idempotency guarantees

The `governance.sync_tars_entities` DAG (every 5 min) is safe to leave running against open PRs:

1. **GitHub delivery guard** — `open_sync_pull_request()` fetches the current file from the PR branch before committing. If the content is identical it skips the PUT entirely, so no spurious commits are created.
2. **Sync state** — after a successful PR open/update the document's content hash is persisted in `TARS_SYNC_STATE_PATH`. On the next run `audit_document` sees `is_unchanged()` → `True` and passes an empty XCom payload, skipping `classify_entity` and `open_pr` entirely.
3. **`force` param** — set the `force` DAG param to `true` to bypass the state cache for a deliberate re-sync.

### Sync commands

```bash
# Default — Direct: push to DataHub + backlink document
uv run python dags/governance/datahub_business_context/sync_tars_entities.py --mode direct

# GitOps: open GitHub PR for engineering review (requires GITHUB_TOKEN with repo write access)
uv run python dags/governance/datahub_business_context/sync_tars_entities.py --mode gitops

# Dry-run: parse and write to sync_output/ locally (or: make validate-context-docs)
uv run python dags/governance/datahub_business_context/sync_tars_entities.py --dry-run

# Single document
uv run python dags/governance/datahub_business_context/sync_tars_entities.py --urn urn:li:document:...

# CI usage — scope to entities whose MD changed in this commit (used by the
# sync-tars-entities Woodpecker step; avoids re-condensing an unrelated,
# already-full product's description on every unrelated push)
uv run python dags/governance/datahub_business_context/sync_tars_entities.py --mode direct --changed-only
```

After GitOps PR merge, CI runs `generate_and_push_datahub_entities.py` as for engineer-authored MDs. Direct mode bypasses Git and calls `load_collections_context.py` directly, then links the Data Product back to the source document.

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
| [`packages/.../generate_and_push_datahub_entities.py`](../../packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py) | CI entry point: MD → ephemeral YAML → push |
| [`sync_tars_entities.py`](./sync_tars_entities.py) | Self-service sync from DataHub Context Documents → YAML / PR / direct push |
| [`context_documents/`](./context_documents/) | Template + authoring guide for non-engineer contributors |
| [`policies/`](./policies/) | DataHub metadata policy specs for `tars-entity` documents |

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

# Golden-query schema gate (Trino syntax + tables/columns vs repo metadata; no execution).
# When DATAHUB_GRAPHQL_URL/DATAHUB_TOKEN are set, tables absent from repo metadata YAML are
# also probed against DataHub before being reported as errors (see README § DataHub fallback).
# Pass --no-datahub-fallback to force repo-metadata-only behavior.
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
