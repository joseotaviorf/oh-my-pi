---
name: md-to-datahub-yaml
description: >
  Convert an existing business entity Markdown file (docs/llm_context/business_entities/*.md)
  into a companion DataHub YAML (dags/governance/datahub_business_context/datahub_entities/*.datahub.yaml).
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
- Called from `create-entity-doc` Step 6 immediately after writing a new Markdown.

---

## Prerequisites — collect before running

Ask the user (or inherit from `create-entity-doc` Step 1) for any items not present in the Markdown:

| Item | Source | Notes |
|------|--------|-------|
| **MD file path** | User or filename | `docs/llm_context/business_entities/{entity}.md` |
| **domain_urn** | User | e.g. `urn:li:domain:growth`. Common: `fintech`, `growth`, `people`, `supply`, `rent`, `sale` |

The `domain_urn` is never present in the Markdown — always ask explicitly.

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
| `golden_query.stable_urn` | Generated | `python -c "import uuid; print(uuid.uuid4())"` — generate once per new entity, never reuse |
| `golden_query.name` | `## Golden Queries` H3 title | First H3 under Golden Queries, e.g. `"Query 1 — Contracts signed in a period"` |
| `golden_query.description` | First sentence below the H3 | One sentence + ` Source: docs/llm_context/business_entities/{entity}.md` |
| `golden_query.subjects` | SQL `FROM` / `JOIN` clauses in first golden query | Extract `schema.table` pairs; map to `- schema: ...\n  table: ...` |
| `golden_query.sql` | First SQL code block under `## Golden Queries` | Verbatim SQL, preserve indentation |
| `datasets` | `## Tables` section | Extract every `schema.table` backtick reference from the table rows; deduplicate |
| `glossary_terms.parent_node_urn` | `domain_urn` | `urn:li:glossaryNode:{domain}` (the part after `urn:li:domain:`) |
| `glossary_terms.terms[].id` | `## Glossary and Synonyms` bullets | snake_case slug from the bold term, e.g. `closing_entity`, `cc2cs_metric` |
| `glossary_terms.terms[].name` | Bullet bold text | The term name as written, e.g. `"Closing (Fechamento)"` |
| `glossary_terms.terms[].description` | Bullet arrow (`→`) text + technical mapping | Expand into a full DataHub description: definition + column/table reference |
| `documentation_link.label` | Entity name | `"Business entity documentation ({entity}.md)"` |
| `documentation_link.url` | Filename | `https://github.com/quintoandar/bi-etl-ejuice/blob/master/docs/llm_context/business_entities/{entity}.md` |

---

## Step 2 — Author `product_description`

The `product_description` is the most important field: it is the primary text shown in DataHub and
consumed by TARS for entity discovery. Condense the `## Overview` section into a focused description.

**Rules:**
- Target: 3–6 paragraphs, 200–400 words total.
- Start with what the entity is and why it matters.
- Include lifecycle stages if present (one sentence each, referencing the key column).
- Include **Critical rules** from `## Dos and Don'ts` or `## Tables` if they affect how data should be queried (mandatory filters, CAST requirements, dedup patterns, grain caveats).
- Include **Key metrics** names in a single paragraph or inline.
- Include **method/status/product_origin** mappings if they are in the Markdown (e.g., payments methods, visit statuses).
- End every description with: `Further detail and table routing: docs/llm_context/business_entities/{entity}.md`
- Do NOT duplicate column-level documentation — reference the column name, not its definition.
- Do NOT mention internal CI/tooling details.

**Quality bar:** compare to `payments.datahub.yaml` `product_description` — that is the gold standard.

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
- Deduplicate.
- Output as:

```yaml
datasets:
  - schema: {schema}
    table: {table}
```

Order: DW tables first (`dw_*`), then enrich (`enrich_*`), then clean/lake (`datalake_*`).

---

## Step 5 — Extract `golden_query`

Use the **first** Golden Query from `## Golden Queries`:

1. **`name`**: verbatim H3 heading, e.g. `"Query 1 — Contracts signed in a period"`.
2. **`description`**: first prose sentence under the H3 (before the SQL block) + ` Source: docs/llm_context/business_entities/{entity}.md`.
3. **`sql`**: verbatim SQL from the first code block. Preserve indentation. Must use Trino SQL dialect (no `QUALIFY`, `GROUP BY ALL`, `IFF`, 3-arg `DATEDIFF`).
4. **`subjects`**: parse `FROM` and `JOIN` clauses in the SQL to extract `schema.table` pairs.

**`stable_urn` — UUID generation:**

```bash
python -c "import uuid; print(uuid.uuid4())"
```

Generate this once. The resulting UUID becomes `urn:li:query:{uuid}`. **Never change it after the first successful push.**

If a companion YAML already exists (update scenario): preserve the existing `stable_urn`. Only generate a new UUID if creating the YAML from scratch.

---

## Step 6 — Write the YAML file

Write to `dags/governance/datahub_business_context/datahub_entities/{entity_slug}.datahub.yaml`.

**Filename rule:** `{entity_slug}` = filename stem of the MD, with underscores converted to hyphens: `broker_xp` → `broker-xp`.

Use `kind: data_product_curated_entity` for all new entities.

Follow the exact structure of `dags/governance/datahub_business_context/datahub_entities/_TEMPLATE.datahub.yaml`. Do not add extra YAML keys not present in the template.

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
golden_query:
  stable_urn: urn:li:query:{uuid}
  name: "Query 1 — ..."
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
- [ ] `domain_urn` matches what the user provided (not inferred)
- [ ] `stable_urn` is a freshly generated UUID4 (not a placeholder `00000000-…`)
- [ ] `product_description` ends with `Further detail and table routing: docs/…`
- [ ] All `schema.table` pairs in `datasets` appear in the Markdown's Tables section
- [ ] `golden_query.sql` is valid Trino SQL (no Spark-only constructs)
- [ ] `golden_query.subjects` match the tables in the SQL
- [ ] Each glossary term has `id` (snake_case), `name`, and `description` populated
- [ ] No YAML keys present that are not in the template

---

## Reference examples

- **Gold standard descriptions:** `dags/governance/datahub_business_context/datahub_entities/payments.datahub.yaml`
- **Gold standard glossary with `related_terms`:** `dags/governance/datahub_business_context/datahub_entities/visits.datahub.yaml`
- **Template:** `dags/governance/datahub_business_context/datahub_entities/_TEMPLATE.datahub.yaml`

---

## After the YAML is written

Inform the user that the YAML is ready. Offer to push it to DataHub:

```bash
# Requires DATAHUB_GRAPHQL_URL and DATAHUB_TOKEN to be set
python dags/governance/datahub_business_context/push_all_entities.py {entity_slug}
```

Verify with:
```bash
python dags/governance/datahub_business_context/smoke_test_datahub.py
```

If the MD file's `## DataHub catalog` section is still a placeholder, offer to back-fill it with:

```markdown
## DataHub catalog

- **Data Product:** [urn:li:dataProduct:{entity_slug}](https://datahub.apps.data-prd.habitat.zone/dataProducts/urn%3Ali%3AdataProduct%3A{entity_slug})
- **Datasets:** listed in `dags/governance/datahub_business_context/datahub_entities/{entity_slug}.datahub.yaml`
```
