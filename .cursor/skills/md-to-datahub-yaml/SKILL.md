---
name: md-to-datahub-yaml
description: >
  Convert an existing business entity Markdown file (docs/llm_context/business_entities/*.md)
  into ephemeral DataHub YAML (CI generates and pushes; not committed to git).
  Use when retrofitting older Markdown files that predate automated YAML generation, or when
  generating the YAML for a single entity without creating the Markdown from scratch.
---

# MD → DataHub YAML Conversion

This skill reads a business entity Markdown file and produces a correctly-structured
`*.datahub.yaml` for the DataHub business-context push pipeline.

---

## When to use this skill

- Retrofitting: an existing `docs/llm_context/business_entities/{entity}.md` has no companion YAML yet.
- Standalone invocation: a single entity's YAML needs updating after the Markdown changed.
- Called from `create-business-entity-doc` Step 6 immediately after writing a new Markdown.

---

## Prerequisites — collect before running

| Item | Source | Notes |
|------|--------|-------|
| **MD file path** | User or filename | `docs/llm_context/business_entities/{entity}.md` |
| **domain_urn** | Live catalog (CI) or user | **CI flow:** CI fetches all domains from DataHub via GraphQL and injects the catalog into the prompt; the LLM infers the best match from that list. **Interactive flow:** ask the user for the URN from the DataHub UI — do not guess. |
| **stable_urn** | Prompt (CI) or generated | If the caller supplies a `stable_urn` value in the prompt (CI flow), use it verbatim. Otherwise generate once with `python -c "import uuid; print(uuid.uuid4())"` and never change it after first push. |

---

## Step 1 — Read the Markdown

Read the full Markdown file. Map sections to YAML fields using the extraction table below.

### Field extraction map

| YAML field | Source in Markdown | Extraction rule |
|---|---|---|
| `product_display_name` | H1 title (`# Entity Name`) | Verbatim title, title-case |
| `data_product_id` | Filename | Convert `{entity}.md` → kebab-case: `broker_xp.md` → `broker-xp` |
| `domain_urn` | Collected from user | Direct use, e.g. `urn:li:domain:growth` |
| `structured_property.qualified_name` | `data_product_id` | `br.com.quintoandar.datahub.{data_product_id}.golden_query` |
| `structured_property.legacy_qualified_names_to_drop` | `data_product_id` | `[br.com.quintoandar.datahub.{data_product_id}.golden_query_url]` |
| `golden_queries[].stable_urn` | — | Always `"TBD"`; CI assigns the deterministic URN per query. |
| `golden_queries[].name` | each `## Golden Queries` H3 title | One entry per H3, e.g. `"Query 1 — Contracts signed in a period"` |
| `golden_queries[].description` | First sentence below each H3 | One sentence + ` Source: docs/llm_context/business_entities/{entity}.md` |
| `golden_queries[].subjects` | SQL `FROM` / `JOIN` clauses in that query | Extract `schema.table` pairs; map to `- schema: ...\n  table: ...` |
| `golden_queries[].sql` | each SQL code block under `## Golden Queries` | Verbatim SQL, preserve indentation |
| `datasets` | `## Tables` section | Extract every `schema.table` backtick reference from the table rows; deduplicate |
| `glossary_terms.parent_node_urn` | `domain_urn` | `urn:li:glossaryNode:{domain}` (the part after `urn:li:domain:`) |
| `glossary_terms.terms[].id` | `## Glossary and Synonyms` bullets | snake_case slug from the bold term, e.g. `closing_entity`, `cc2cs_metric` |
| `glossary_terms.terms[].name` | Bullet bold text | The term name as written, e.g. `"Closing (Fechamento)"` |
| `glossary_terms.terms[].description` | Bullet arrow (`→`) text + technical mapping | Expand into a full DataHub description: definition + column/table reference |
| `documentation_link.label` | Entity name | `"Business entity documentation ({entity}.md)"` |
| `documentation_link.url` | Filename | `https://github.com/quintoandar/bi-etl-ejuice/blob/master/docs/llm_context/business_entities/{entity}.md` |

---

## Step 2 — `product_description` (do NOT hand-author)

**CI overwrites `product_description` with the full Markdown body**, minus the sections that map to
other DataHub features:

- `## Tables` / `## Where to query what` → linked assets
- `## Synonyms` / `## Glossary and Synonyms` → glossary terms
- `## Golden Queries` (and variants) → Query entities
- `## DataHub catalog` → tooling pointer only

Everything else — Overview, Key Metrics, Critical rules, Dos and Don'ts, Relationships with Other
Entities, and all entity-specific sections — IS the description, verbatim from the MD.

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

The `## Glossary and Synonyms` section in the Markdown is a bullet list. Expand each bullet into a full DataHub term entry.

**For each bullet `- **{term}** ({aliases}) → {mapping}`:**

```yaml
- id: {snake_case_slug}        # derive from term name, keep short
  name: "{term} ({PT-BR alias or aliases if short})"
  description: >-
    {Full plain-language definition (2-5 sentences). Must include:}
    {- What the concept means in business terms}
    {- The table and column where it is encoded}
    {- Any filter value (e.g. status = 'PAID', role = 'tenant')}
    {- Why it matters for analysts (when to use it)}
```

**`related_terms` guidance:**
- Add `related_terms` when the term is clearly a sub-type (`isA`) or contains another term (`hasA`).
- Do NOT add `related_terms` for terms that are not yet defined in DataHub.
- Use `urn:li:glossaryTerm:{id}` where `{id}` is the snake_case slug defined in this file or another entity's YAML.
- Relationship types: `isA` (inherits), `hasA` (contains). Human aliases: `inherits`, `inherited_by`, `contains`, `contained_by`.

**Bullet format variants the MD may contain:**
- `- **term** → mapping` (simple)
- `- **term** (aliases) → mapping` (with aliases)
- `- **term** → mapping; additional detail` (with detail after semicolon)

All forms are valid input — extract term name, aliases, and mapping text for the description.

**Limit:** aim for 5–10 terms. Omit terms that are company-wide jargon (IQ, PP) or purely structural (column names without business meaning).

---

## Step 4 — Extract `datasets`

Scan the `## Tables` section for every `` `schema.table` `` backtick pair (also written as `` `schema.table` `` inside table rows or critical rules).

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

---

## Step 5 — Extract `golden_queries` (ALL of them)

Emit **every** Golden Query from `## Golden Queries` as a `golden_queries:` **list** (plural).
Do NOT stop at the first — a product with 17 queries in its MD must produce 17 list entries.

For each query (in document order):

1. **`name`**: verbatim H3 heading, e.g. `"Query 1 — Contracts signed in a period"`.
2. **`description`**: first prose sentence under the H3 (before the SQL block) + ` Source: docs/llm_context/business_entities/{entity}.md`.
3. **`sql`**: verbatim SQL from that query's code block. Preserve indentation. Must use Trino SQL dialect (no `QUALIFY`, `GROUP BY ALL`, `IFF`, 3-arg `DATEDIFF`).
4. **`subjects`**: parse `FROM` and `JOIN` clauses in that query's SQL to extract `schema.table` pairs.
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
product_description: |
  ...
data_product_id: ...
domain_urn: urn:li:domain:{domain}
structured_property:
  qualified_name: br.com.quintoandar.datahub.{slug}.golden_query
  legacy_qualified_names_to_drop:
    - br.com.quintoandar.datahub.{slug}.golden_query_url
golden_queries:
  - stable_urn: "TBD"          # CI assigns the deterministic URN
    name: "Query 1 — ..."
    description: >-
      ...
    subjects:
      - schema: ...
        table: ...
    sql: |
      ...
  - stable_urn: "TBD"
    name: "Query 2 — ..."
    description: >-
      ...
    subjects:
      - schema: ...
        table: ...
    sql: |
      ...
datasets:
  - schema: ...
    table: ...
glossary_terms:
  parent_node_urn: urn:li:glossaryNode:{domain}
  terms:
    - id: ...
      name: "..."
      description: >-
        ...
documentation_link:
  label: "Business entity documentation ({entity}.md)"
  url: >-
    https://github.com/quintoandar/bi-etl-ejuice/blob/master/docs/llm_context/business_entities/{entity}.md
```

---

## Step 7 — Self-review checklist

Before presenting the YAML to the user:

- [ ] `data_product_id` is kebab-case and matches filename stem
- [ ] `datasets` lists only concrete `schema.table` pairs — no `*`, no `schema.*`, no ellipsis placeholders
- [ ] `domain_urn` matches what the user provided (not inferred)
- [ ] `stable_urn` matches the value provided in the prompt (do not rotate)
- [ ] `product_description` ends with `Further detail and table routing: docs/…`
- [ ] All `schema.table` pairs in `datasets` appear in the Markdown's Tables section
- [ ] `golden_query.sql` is valid Trino SQL (no Spark-only constructs)
- [ ] `golden_query.subjects` match the tables in the SQL
- [ ] Each glossary term has `id` (snake_case), `name`, and `description` populated
- [ ] Glossary `id` matches the slug already in DataHub when the term exists (loader resolves by `name` as fallback, but `related_terms` URNs must use real ids)
- [ ] No YAML keys present that are not in the template

---

## Reference examples

- **Gold standard descriptions:** `dags/governance/datahub_business_context/reference/payments.datahub.yaml`
- **Gold standard glossary with `related_terms`:** `dags/governance/datahub_business_context/reference/visits.datahub.yaml`
- **Template:** `dags/governance/datahub_business_context/reference/_TEMPLATE.datahub.yaml`

---

## After the YAML is written

Inform the user that CI will publish on merge. To push locally:

```bash
export OPENAI_API_KEY=... DATAHUB_GRAPHQL_URL=... DATAHUB_TOKEN=...
uv run --script packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py \\
  docs/llm_context/business_entities/{entity}.md
```

Verify with:
```bash
python dags/governance/datahub_business_context/smoke_test_datahub.py
```

If the MD file's `## DataHub catalog` section is still a placeholder, offer to back-fill it with:

```markdown
## DataHub catalog

- **Data Product:** [urn:li:dataProduct:{entity_slug}](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3A{entity_slug})
- **Datasets:** listed in the generated YAML (CI) from the Markdown `## Tables` section
```
