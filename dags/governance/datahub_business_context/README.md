# DataHub business context (curated Data Products)

This folder holds the **YAML-driven pipeline** that publishes curated **Data Products** into [DataHub](https://github.com/acryldata/datahub): product copy, dataset links, glossary terms, golden SQL (Query entities), sidebar structured properties (URN pointer from product to query), and a documentation link—usually to the canonical entity Markdown on GitHub.

Consumers such as **TARS** use the **DataHub MCP** (`search`, `get_entities`, `list_schema_fields`, `get_dataset_queries`, etc.) against the published catalog **without cloning** this repo. In-repo narratives, JOIN recipes, and dos-and-don’ts live under [`docs/llm_context/business_entities/`](../../../docs/llm_context/business_entities/); discovery order for analysis is summarized in [`docs/llm_context/intro.md`](../../../docs/llm_context/intro.md).

---

## End-to-end flow (FigJam)

Authoring pushes **catalog facts** into DataHub; Markdown stays the **human source of truth** for depth and nuance inside the warehouse repo.

**[DataHub business context authoring flow — open in FigJam](https://www.figma.com/board/TmOjz5L6iAUVrDZbKf9qLO)**

Nodes (high level):

1. **Entity Markdown** — written from [`docs/llm_context/business_entities/_TEMPLATE.md`](../../../docs/llm_context/business_entities/_TEMPLATE.md).
2. **Companion YAML** — preset under [`datahub_entities/`](./datahub_entities/) (copy from `_TEMPLATE.datahub.yaml`), maintained **in sync** with the `.md`; see **Authoring expectation** below.
3. **`push_all_entities.py` / loader** — runs [`load_collections_context.py`](./load_collections_context.py) per config (`--config`).
4. **DataHub** — GraphQL mutations apply changes (idempotent / safe to retry).
5. **TARS** — answers questions using **DataHub MCP** backed by published products and datasets.

This README does **not** embed Mermaid; the canonical diagram lives in FigJam above.

---

## Authoring expectation: Markdown versus YAML

- **Governance goal:** Whenever the entity story tables or synonyms change materially, authors **bring the companion YAML up to date** in the same change (same PR mentality). That keeps DataHub MCP answers aligned with the narrative docs—think of YAML as **structured serialization** of the catalog-facing slice of that story, not a second parallel spec.
- **What this repo does *not* do:** There is **no built-in importer** here that parses `*.md` and emits `*.datahub.yaml`. [`load_collections_context.py`](./load_collections_context.py) consumes **YAML only**. Steps 1–2 in [`datahub_entities/_TEMPLATE.datahub.yaml`](./datahub_entities/_TEMPLATE.datahub.yaml) (“write `.md`, then write/update YAML”) are intentional.

---

## Layout (what lives where)

| Path | Role |
|------|------|
| [`datahub_entities/*.datahub.yaml`](./datahub_entities/) | `spec_version: 1` presets: product metadata, datasets, glossary, golden query, doc link (`_TEMPLATE` plus one file per entity). Bulk push skips files whose basename starts with `_` (templates only). |
| [`load_collections_context.py`](./load_collections_context.py) | Loads YAML, executes GraphQL mutations (`kind: data_product_curated_entity`). |
| [`push_all_entities.py`](./push_all_entities.py) | Sequential wrapper: invokes the loader once per non-`_`-prefixed `*.datahub.yaml`. |
| [`smoke_test_datahub.py`](./smoke_test_datahub.py) | Read-only check: Data Product URNs inferred from YAML exist in DataHub. |
| [`datahub_curated_urns.py`](./datahub_curated_urns.py) | Pydantic URNs / structured-property helpers shared by the loader. |

---

## YAML `kind`

[`load_collections_context.py`](./load_collections_context.py) accepts one kind:

| `kind` | When to use |
|--------|-------------|
| **`data_product_curated_entity`** | Declarative YAML—datasets (with optional per-dataset `description` and per-field `fields`), glossary, golden query SQL, sidebar structured property, and documentation URL. All entities use this. |

---

## Authoring playbook (new or updated entity)

1. Draft or revise **`docs/llm_context/business_entities/<entity_slug>.md`** using [`_TEMPLATE.md`](../../../docs/llm_context/business_entities/_TEMPLATE.md) (grain, synonyms, joins, pitfalls).
2. Copy **`datahub_entities/_TEMPLATE.datahub.yaml`** → **`datahub_entities/<entity_slug>.datahub.yaml`** (kebab-case slug, matches `data_product_id` conventions in existing files). Fill **`product_display_name`**, **`product_description`**, **`datasets`**, **`glossary_terms`**, **`golden_query`** (stable **`stable_urn`** after first successful push—do **not** rotate casually), **`documentation_github_url`**.
3. Confirm every **`schema.table`** you list exists in DataHub before pushing.
4. Push (see commands below). Run **`smoke_test_datahub.py`** if you changed product definitions.

---

## Prerequisites and commands

Exports (typical):

```bash
export DATAHUB_GRAPHQL_URL="https://<your-datahub-host>/api/graphql"
export DATAHUB_TOKEN="<personal-access-token-with-editor-role>"
# Optional: Habitat UI origin for stale discovery-link cleanup
# export DATAHUB_UI_ORIGIN="https://datahub.apps.data-prd.habitat.zone"
```

From the **`bi-etl-ejuice` repo root**:

```bash
# Default config: datahub_entities/collections-recovery.datahub.yaml (see loader --help)
python dags/governance/datahub_business_context/load_collections_context.py

# Explicit single entity
python dags/governance/datahub_business_context/load_collections_context.py \
  --config dags/governance/datahub_business_context/datahub_entities/ticket.datahub.yaml

# All entities sequentially (skips filenames starting with "_")
python dags/governance/datahub_business_context/push_all_entities.py

# Single slug (suffix .datahub.yaml optional)
python dags/governance/datahub_business_context/push_all_entities.py chatbot-sessions

# Verify Data Products exist (requires same GraphQL URL + token)
python dags/governance/datahub_business_context/smoke_test_datahub.py
python dags/governance/datahub_business_context/smoke_test_datahub.py --verbose
```

Exit codes mirror the sequential shell wrapper: loaders exit non-zero when mutations fail; **`push_all_entities.py`** aggregates per-entity results and exits **1** if any push failed.

---

## TARS and in-repo Markdown

After a successful push, **TARS** should prefer **DataHub MCP** for schema fields, glossary, and curated queries tied to Data Products **before** leaning only on Markdown in `docs/llm_context/`. For exploratory SQL authoring rules loaded with **`@tars`**, see [`data_exploration.mdc`](../../../.cursor/rules/data_exploration.mdc).

---

## Related tooling

TARS pivot benchmark reports, eval fixtures, and helper scripts live under [`docs/benchmark/datahub/`](../../../docs/benchmark/datahub/). They are **not** required to publish YAML to DataHub — use them when iterating on MCP or analyst answer quality.
