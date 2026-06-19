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
| `push-datahub-business-context` | push to master / hotfix | MD → YAML → push (changed MDs; all MDs if loader changed) |
| `validate-datahub-entities-post-push` | push (after generate) | smoke test: changed MDs have a live Data Product |
| `validate-datahub-entities` | pull request | smoke test: full catalog |
| `sync-tars-entities` | push (sync path changes) | Context Documents tagged `tars-entity` → Data Product (direct mode) |
| `push-context-documents` | push (context doc changes) | Publish guide + template Markdown as DataHub Context Documents |

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
```

After GitOps PR merge, CI runs `generate_and_push_datahub_entities.py` as for engineer-authored MDs. Direct mode bypasses Git and calls `load_collections_context.py` directly, then links the Data Product back to the source document.

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

# Loader only (debug with reference example)
python dags/governance/datahub_business_context/load_collections_context.py \
  --config dags/governance/datahub_business_context/reference/payments.datahub.yaml
```

---

## Related tooling

[`benchmark_report.md`](benchmark_report.md) and eval scripts are benchmarking utilities — not required for day-to-day publication.
