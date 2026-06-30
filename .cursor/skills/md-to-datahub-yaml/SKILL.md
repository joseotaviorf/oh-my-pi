---
name: md-to-datahub-yaml
description: >
  Convert an existing entity Markdown file (docs/llm_context/business_entities/*.md or
  docs/llm_context/metric_entities/*.md) into ephemeral DataHub YAML (CI generates and
  pushes; not committed to git). Use when retrofitting older Markdown files that predate
  automated YAML generation, or when generating the YAML for a single entity without
  creating the Markdown from scratch.
---

# MD → DataHub YAML Conversion

This skill reads a **domain** (business) or **metric** entity Markdown file and produces a
correctly-structured `*.datahub.yaml` for the DataHub business-context push pipeline.

Authoring templates (source of truth for section names):

| Type | Template |
|------|----------|
| Domain / business entity | `docs/llm_context/business_entities/_TEMPLATE.md` |
| Metric entity | `docs/llm_context/metric_entities/_TEMPLATE.md` |
| YAML schema | `dags/governance/datahub_business_context/reference/_TEMPLATE.datahub.yaml` |

---

## When to use this skill

- Retrofitting: an existing entity `.md` has no companion YAML yet.
- Standalone invocation: a single entity's YAML needs updating after the Markdown changed.
- Called from `create-business-entity-doc` / `create-metric-entity-doc` after writing a new Markdown.

---

## Prerequisites — collect before running

| Item | Source | Notes |
|------|--------|-------|
| **MD file path** | User or filename | `docs/llm_context/business_entities/{entity}.md` **or** `docs/llm_context/metric_entities/{metric}.md` |
| **data_product_type** | Directory | `domain` for `business_entities/`; `metric` for `metric_entities/` |
| **domain_urn** | Live catalog (CI) or user | **CI flow:** CI fetches all domains from DataHub via GraphQL and injects the catalog into the prompt; the LLM infers the best match from that list. **Interactive flow:** ask the user for the URN from the DataHub UI — do not guess. |
| **stable_urn** | Prompt (CI) or generated | If the caller supplies a `stable_urn` value in the prompt (CI flow), use it verbatim. Otherwise generate once with `python -c "import uuid; print(uuid.uuid4())"` and never change it after first push. |

---

## Step 1 — Read the Markdown

Read the full Markdown file. Map sections to YAML fields using the extraction table below.

### Field extraction map (shared)

| YAML field | Source in Markdown | Extraction rule |
|---|---|---|
| `product_display_name` | H1 title (`# Entity Name`) | Verbatim title |
| `data_product_id` | Filename | Convert `{entity}.md` → kebab-case: `broker_xp.md` → `broker-xp` |
| `data_product_type` | Directory | `domain` (business_entities) or `metric` (metric_entities) |
| `domain_urn` | Collected from user / CI catalog | Direct use, e.g. `urn:li:domain:growth` |
| `lifecycle_stage` | Default | `prod` unless Markdown indicates draft/review/deprecated |
| `structured_property.qualified_name` | Fixed | `br.com.quintoandar.datahub.data_product.golden_query` |
| `structured_property.legacy_qualified_names_to_drop` | `data_product_id` | `[br.com.quintoandar.datahub.{id}.golden_query, ...golden_query_url]` |
| `golden_queries[].stable_urn` | — | Always `"TBD"`; CI assigns the deterministic URN per query. |
| `golden_queries[].name` | Golden query heading | See Step 5 |
| `golden_queries[].description` | First sentence below each query heading | One sentence + ` Source: docs/llm_context/{subdir}/{entity}.md` |
| `golden_queries[].subjects` | SQL `FROM` / `JOIN` clauses in that query | Extract `schema.table` pairs; map to `- schema: ...\n  table: ...` |
| `golden_queries[].sql` | SQL code block under the golden-query section | Verbatim SQL, preserve indentation; Trino dialect |
| `glossary_terms.parent_node_urn` | `domain_urn` | `urn:li:glossaryNode:{domain}` (the part after `urn:li:domain:`) |
| `documentation_link.label` | Entity kind + filename | `"Business entity documentation ({entity}.md)"` or `"Metric entity documentation ({entity}.md)"` |
| `documentation_link.url` | Filename + directory | `https://github.com/quintoandar/bi-etl-ejuice/blob/master/docs/llm_context/{subdir}/{entity}.md` |

### Domain entity only (`business_entities/`)

| YAML field | Source in Markdown | Extraction rule |
|---|---|---|
| `datasets` | `## Where to query what` + per-schema table sections | Extract every `` `schema.table` `` backtick reference; deduplicate; primary-owner only (Step 4) |
| `glossary_terms.terms[].id` | `## Synonyms` table | snake_case slug from the bold Term column |
| `glossary_terms.terms[].name` | Synonyms table Term column | As written, e.g. `"Closing (Fechamento)"` |
| `glossary_terms.terms[].description` | Synonyms table Meaning + Notes | Expand into a full DataHub description |

### Metric entity only (`metric_entities/`)

| YAML field | Source in Markdown | Extraction rule |
|---|---|---|
| `datasets` | `## Superset Golden Assets` | Extract every `` `schema.table` `` backtick pair **and** every Superset ``urn:li:dataset:(urn:li:dataPlatform:superset,...)`` URN. CI injects both as reference assets on the product Summary (nps-fr pattern). |
| `related_data_products` | `## Related Business Entities` bullets | Convert each entity display name to kebab-case id (`NPS` → `nps`, `House and Listing` → `house-and-listing`). CI also injects this list. |
| `glossary_terms.terms[].id` | `## Glossary and Synonyms` bullets | snake_case slug from the primary bold term |
| `glossary_terms.terms[].name` | Bullet bold text | The term name as written |
| `glossary_terms.terms[].description` | Bullet arrow (`→`) text | Expand into a full DataHub description |

---

## Step 2 — `product_description` (do NOT hand-author)

**CI overwrites `product_description` with the full Markdown body**, minus the sections that map to
other DataHub features:

| Section (domain or metric) | Maps to |
|---|---|
| `## Where to query what` / legacy `## Tables` | linked assets (`datasets`) — domain only |
| `## Superset Golden Assets` | Trino tables + Superset URNs → `datasets:` reference assets — metric only |
| `## Synonyms` / `## Glossary and Synonyms` | glossary terms |
| `## Golden query:` / `## Golden Queries` | Query entities |
| `## DataHub catalog` / `## DataHub Catalog` | tooling pointer only |
| `## Related Business Entities` | upstream data products SP (metric only) |

Everything else — Overview, Scope, Calculation, Dos and Don'ts, Relationships, per-schema
field guides, etc. — IS the description, verbatim from the MD.

**Rule:** emit a one-line placeholder in the YAML; never condense or summarize:

```yaml
product_description: "(injected by CI from Markdown)"
```

The extraction + injection happens in
`packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py`
(`_extract_description_from_md` → `_inject_description`). There is no word-count target — the full
content is the deliverable. Keep the MD itself well-structured; that is where description quality
is controlled now.

---

## Step 3 — Author `glossary_terms`

### Domain — `## Synonyms` table

For each table row (`| **{term}** | {meaning} | {notes} |`):

```yaml
- id: {snake_case_slug}        # derive from term name, keep short
  name: "{term}"
  description: >-
    {Full plain-language definition (2-5 sentences). Must include:}
    {- What the concept means in business terms}
    {- The table and column where it is encoded}
    {- Any filter value (e.g. status = 'PAID', role = 'tenant')}
    {- Why it matters for analysts (when to use it)}
```

### Metric — `## Glossary and Synonyms` bullets

For each bullet `- **{term}**, **{synonym}** → {mapping}`:

```yaml
- id: {snake_case_slug}
  name: "{primary term name}"
  description: >-
    {Full definition including mapping text and when analysts use this name}
```

**`related_terms` guidance:**
- Add `related_terms` when the term is clearly a sub-type (`isA`) or contains another term (`hasA`).
- Do NOT add `related_terms` for terms that are not yet defined in DataHub.
- Use `urn:li:glossaryTerm:{id}` where `{id}` is the snake_case slug defined in this file or another entity's YAML.
- Relationship types: `isA` (inherits), `hasA` (contains). Human aliases: `inherits`, `inherited_by`, `contains`, `contained_by`.

**Limit:** aim for 5–10 terms. Omit terms that are company-wide jargon (IQ, PP) or purely structural (column names without business meaning).

---

## Step 4 — Extract `datasets`

### Domain entities (`business_entities/`)

Scan `## Where to query what` and per-schema H2 sections for every `` `schema.table` `` backtick pair.

- Keep only `schema.table` pairs where the schema looks like a real Databricks schema (e.g., `dw_rent`, `datalake_checkout_clean`, `enrich_visits`).
- **Never emit wildcards or patterns in `datasets`.** DataHub links concrete dataset URNs only. Skip (do not copy to YAML) any reference containing `*`, `…`, or placeholder suffixes like `statement_*`, `reverse_accounts_*`, or `schema.*`. If the Markdown uses a pattern for narrative routing, expand to the real table names listed elsewhere in the same doc, or omit from `datasets` entirely.
- **CRITICAL — list ONLY tables this product is the PRIMARY OWNER of.** `batchSetDataProduct` is *exclusive*: a dataset can belong to exactly one Data Product. Listing a table owned by another product would steal it and break that product. A table you only JOIN to (owned by another domain) belongs in the description prose / JOIN notes — **not** in `datasets:`.
  - Primary owner = the product whose domain schema the table lives in. Use this schema-prefix → owner guide:

    | Schema prefix | Primary owner |
    |---|---|
    | `datalake_chatbot.*` | `chatbot-sessions` |
    | `datalake_langfuse_clean.*` | `evals` |
    | `datalake_conversation_explorer_clean.*` | `conversation-explorer` |
    | `datalake_ai_collections_quintoandar.*`, `dw_collection_ai_agents.*` | `matthew` |
    | `dw_collections_segmentation.*` | `collections` |
    | `datalake_debt_recovery.*`, `metric_fintech.daily_recovery_*`, `dw_evictions.*` | `recovery-collections-fr-tenants` |
    | `dw_payments_platform.*`, `datalake_checkout_clean.*`, `datalake_wall_street_clean.*`, `datalake_vans_clean.*` | `payments` |
    | `dw_customer_support.fact_chat_messages` | `contact` |
    | `dw_customer_support.fact_tickets`, `datalake_customer_support.tickets` | `ticket` |

  - When unsure who owns a shared table, leave it OUT of `datasets:` and mention it in the description instead. The loader has a backstop (`_filter_assignable_urns` in `load_collections_context.py`) that refuses to reassign a table already owned by a different product and logs the conflict — but authoring it correctly here is the real fix.
- Deduplicate.
- Output as:

```yaml
datasets:
  - schema: {schema}
    table: {table}
```

Order: DW tables first (`dw_*`), then enrich (`enrich_*`), then clean/lake (`datalake_*`).

### Metric entities (`metric_entities/`)

Parse `## Superset Golden Assets` for **both** Trino tables and Superset virtual-dataset URNs —
all are reference assets on the Data Product Summary (same pattern as [nps-fr](https://datahub.apps.data-prd.habitat.zone/dataProduct/urn:li:dataProduct:nps-fr/Summary)):

```yaml
datasets:
  - schema: sandbox
    table: nps_fr
  - schema: sandbox
    table: nps_onb_cohort
  - urn: urn:li:dataset:(urn:li:dataPlatform:superset,16266,PROD)
  - urn: urn:li:dataset:(urn:li:dataPlatform:superset,15745,PROD)
```

- Trino rows resolve via DataHub platform probe (Trino `hive.{schema}.{table}` first, then Databricks).
- Superset rows use explicit `urn:` — no platform probing.
- Omit `datasets:` when the Markdown declares no tables and no Superset URNs.
- Include every `` `schema.table` `` and Superset URN in backticks so CI can extract them deterministically.
- The loader refuses to steal a Trino table already owned by a **different** domain product (`_filter_assignable_urns`); sandbox tables materialized for the metric are typically safe to link.

---

## Step 5 — Extract `golden_queries` (ALL of them)

Emit **every** golden query from the Markdown as a `golden_queries:` **list** (plural).

**Domain docs** may use either form:
- Singular: `## Golden query: {Query Name}` — one entry; `name` = the part after the colon.
- Plural: `## Golden Queries` with `### Query N — …` sub-headings.

**Metric docs** use `## Golden Queries` (usually one canonical query).

For each query (in document order):

1. **`name`**: heading text (H2 suffix or H3 title), e.g. `"AR recovery rate (C&E / Neotribe-style)"` or `"Query 1 — Contracts signed in a period"`.
2. **`description`**: first prose sentence under the heading (before the SQL block) + ` Source: docs/llm_context/{subdir}/{entity}.md`.
3. **`sql`**: verbatim SQL from that query's code block. Preserve indentation. Must use Trino SQL dialect (no `QUALIFY`, `GROUP BY ALL`, `IFF`, 3-arg `DATEDIFF`).
4. **`subjects`**: parse `FROM` and `JOIN` clauses in that query's SQL to extract `schema.table` pairs. For metric queries whose final SELECT reads from a CTE only, include subjects from inner CTEs or rely on the loader's product-level subject pool fallback.
5. **`stable_urn`**: always `"TBD"` — CI assigns the real deterministic URN per query
   (`uuid5(slug)` for query 0, `uuid5(slug:N)` for the rest). Do NOT invent a UUID.

The legacy singular `golden_query:` (one mapping) is still accepted by the loader, but new
entities should always use the plural list form.

---

## Step 6 — Output the YAML

Output valid YAML only (CI writes it to a temp file — do not reference a repo path).

**Filename rule:** `data_product_id` = MD filename stem with underscores → hyphens: `broker_xp` → `broker-xp`.

Use `kind: data_product_curated_entity` for all new entities.

Follow the exact structure of `dags/governance/datahub_business_context/reference/_TEMPLATE.datahub.yaml`.

**Minimum required fields (all must be present):**

```yaml
spec_version: 1
kind: data_product_curated_entity
product_display_name: "..."
product_description: "(injected by CI from Markdown)"
data_product_id: ...
domain_urn: urn:li:domain:{domain}
lifecycle_stage: prod
data_product_type: domain  # or metric
structured_property:
  qualified_name: br.com.quintoandar.datahub.data_product.golden_query
  legacy_qualified_names_to_drop:
    - br.com.quintoandar.datahub.{slug}.golden_query
    - br.com.quintoandar.datahub.{slug}.golden_query_url
golden_queries:
  - stable_urn: "TBD"
    name: "..."
    description: >-
      ...
    subjects:
      - schema: ...
        table: ...
    sql: |
      ...
glossary_terms:
  parent_node_urn: urn:li:glossaryNode:{domain}
  terms:
    - id: ...
      name: "..."
      description: >-
        ...
documentation_link:
  label: "Business entity documentation ({entity}.md)"  # or Metric entity ...
  url: >-
    https://github.com/quintoandar/bi-etl-ejuice/blob/master/docs/llm_context/{subdir}/{entity}.md
```

**Metric-only optional fields:**

```yaml
datasets:
  - schema: sandbox
    table: nps_fr
  - urn: urn:li:dataset:(urn:li:dataPlatform:superset,{id},PROD)

related_data_products:
  - nps
  - supply
```

**Domain-only field:**

```yaml
datasets:
  - schema: ...
    table: ...
```

---

## Step 7 — Self-review checklist

Before presenting the YAML to the user:

- [ ] `data_product_id` is kebab-case and matches filename stem
- [ ] `data_product_type` matches source directory (`domain` vs `metric`)
- [ ] Domain: `datasets` lists only primary-owner concrete `schema.table` pairs — no wildcards
- [ ] Metric: `datasets` lists Trino `schema`/`table` reference tables **and** Superset `urn:` entries when declared in MD
- [ ] `domain_urn` matches what the user provided (not inferred)
- [ ] `stable_urn` is `"TBD"` on every golden query (CI assigns)
- [ ] All golden-query SQL is valid Trino (no Spark-only constructs)
- [ ] Each glossary term has `id` (snake_case), `name`, and `description` populated
- [ ] `documentation_link.url` points to the correct `{subdir}/{entity}.md` path
- [ ] `structured_property.qualified_name` is `br.com.quintoandar.datahub.data_product.golden_query`
- [ ] No YAML keys present that are not in the template

---

## Reference examples

- **Gold standard descriptions:** `dags/governance/datahub_business_context/reference/payments.datahub.yaml`
- **Gold standard glossary with `related_terms`:** `dags/governance/datahub_business_context/reference/visits.datahub.yaml`
- **Template:** `dags/governance/datahub_business_context/reference/_TEMPLATE.datahub.yaml`
- **Domain MD template:** `docs/llm_context/business_entities/_TEMPLATE.md`
- **Metric MD template:** `docs/llm_context/metric_entities/_TEMPLATE.md`

---

## After the YAML is written

Inform the user that CI will publish on merge. To push locally:

```bash
export OPENAI_API_KEY=... DATAHUB_GRAPHQL_URL=... DATAHUB_TOKEN=...
uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py \
  docs/llm_context/business_entities/{entity}.md
# or
uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py \
  docs/llm_context/metric_entities/{metric}.md
```

Verify with:
```bash
uv run python dags/governance/datahub_business_context/smoke_test_datahub.py
```

If the MD file's `## DataHub catalog` section is still a placeholder, offer to back-fill it with:

```markdown
## DataHub catalog

- **Data Product:** [urn:li:dataProduct:{entity_slug}](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3A{entity_slug})
- **Datasets:** listed in the generated YAML (CI) from the Markdown routing sections (domain only)
```
