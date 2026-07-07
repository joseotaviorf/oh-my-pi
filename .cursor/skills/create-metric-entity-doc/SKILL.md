---
name: create-metric-entity-doc
description: Create a new metric entity documentation file in docs/llm_context/metric_entities/. Metric entity docs are thin on schema and thick on calculation — they define ONE official, named metric with its exact formula, scope, canonical filter, weight/parameter sources, and the single canonical query that reproduces the source-of-truth number. Use when the user asks to document a new official metric, add a metric entity, or define how TARS should compute an official indicator.
---

# Create a Metric Entity Doc

Metric entity docs are **calculation contracts** — they tell TARS (and analysts) *exactly* how to compute an official metric: scope, formula, canonical filter, parameter sources, and a single golden query. They are **not** schema guides; schema lives in the linked business entity under `docs/llm_context/business_entities/`. When both files touch the same domain, this metric entity **overrides** the generic calculation in the business entity.

---

## Step 1 — Gather context from the user

**Always ask the user** for the following (use the AskQuestion tool). Only skip items the user already provided explicitly in their request:

1. **Metric name** — the official name used by the business (e.g., `NPS FR`, `GMV FS`, `FL 1P`). File will be `docs/llm_context/metric_entities/{metric_slug}.md` (lowercase snake_case, e.g., `nps_fr.md`).
2. **One-line definition** — what the metric measures and how it differs from a naive/component calculation.
3. **Product scope** — does the metric exist for a specific product only (e.g., For Rent, For Sale, all)? Note restrictions clearly.
4. **Related business entity** — which existing file(s) in `docs/llm_context/business_entities/` own the underlying tables and columns for this metric. If unknown, proceed to Step 2 to discover them.
5. **Scope (included / excluded)** — journeys, segments, audiences, campaign purposes that count vs. those that don't.
6. **Official formula** — the exact calculation, especially when weighting, pooling, or multi-step aggregation is involved.
7. **Canonical filter** — the exact SQL predicates that define the metric's universe (mandatory fields + values).
8. **Weight / parameter source** — where do coefficients, targets, or thresholds live (e.g., a GSheets table)? Never hardcode.
9. **Common analyst mistakes** — the top 2–3 traps that produce a wrong number (drives Dos and Don'ts and the warning in Canonical Filter).
10. **Superset golden assets** — the reference assets for this metric: canonical Superset virtual datasets and/or the materialized Trino/Databricks `schema.table` tables they map to (e.g. `sandbox.nps_fr`). These are linked as reference assets on the DataHub Data Product Summary. Optional.
11. **Ownership emails** — at least one **Data Owner** (accountable for the business definition, usually a manager/lead) and at least one **Data Steward** (`@quintoandar.com.br`, maintains this document day-to-day; defaults to the requester if not otherwise specified). The two roles may share the same email.
12. **MBR membership** — does this metric feed one or more Monthly Business Reviews (MBRs)? If so, which one(s)? Optional — omit if the metric is not part of any MBR. A metric may belong to several MBRs.

Do NOT infer formula details from context — the whole point of this file is to be the definitive source of truth.

---

## Step 2 — Research the codebase

Before writing, verify the data model and calculation. Launch parallel explore subagents to:

1. **Find the metric SQL** — search `dags/*/metric_*/queries/metric/` and `dags/*/dw_*/queries/dw/` for tables or views that implement this metric. Read the SQL to understand the formula, CTEs, and filters already in production.
2. **Find the component SQL in the business entity** — if a related business entity exists, read its file and its DW SQL to understand the component calculation this metric builds on.
3. **Read governance metadata** — check `metadata/metric/*.yml` and `metadata/dw/*.yml` for the tables involved. Use column names and descriptions from there — do NOT re-document columns.
4. **Find the weight/parameter table** — if the metric uses GSheets weights or parameter tables, find the clean metadata YAML for those tables and note the exact column names and parsing patterns (e.g., string `'25%'` → `CAST(REPLACE(share, '%', '') AS DOUBLE) / 100.0`).
5. **Validate columns via Trino** (if available) — use `describe_table` on the main metric/DW table to confirm column names and types before writing the golden query.
6. **Look for dedup / fallback patterns** — check if there are `ROW_NUMBER()` dedup guards, fallback logic for missing periods, or overlap protection in the GSheet (duplicated rows).

---

## Step 3 — Write the metric entity file

Create `docs/llm_context/metric_entities/{metric_slug}.md` following the template below exactly. Every section is required except **Superset Golden Assets** (optional when the metric has no Trino table and no Superset asset to link). Keep the file concise: thick on calculation, thin on schema.

### Template

```markdown
# {Official Metric Name}

## Ownership

**Data Owner:**
- {data_owner_email@quintoandar.com.br}

**Data Steward:**
- {data_steward_email@quintoandar.com.br}

## Overview

**{Name}** is {one-sentence definition}. {How it differs from the naive/component calculation — why the business rule exists}.

**{Product-scope restriction, if any — e.g. "Exists exclusively for For Rent."}**

## Related Business Entities

- {Business Entity Name}

## MBR

<!-- Optional — one bullet per MBR this metric feeds. Omit the whole section if none. -->

- {MBR Name}

## Glossary and Synonyms

- **{term}**, **{synonym}**, **{official name}** → this metric

## Scope

**Included**: {journeys, segments, audiences, campaign purposes}

**Excluded**: {what does NOT count — test campaigns, out-of-scope segments, etc.}

## Calculation

{Explain why the naive path produces a wrong result, if applicable.}

The correct calculation is:

```
{Metric} = {formula, e.g. weighted sum of components}
```

where {definition of each term / component}.

### Canonical Filter

Apply on `{table/dim}`:

```sql
{field_1} = '{value}'
AND {field_2} = '{value}'
```

**Warning**: {the most common under-filtering mistake and what it incorrectly includes}.

### Nuances

{Where the weights/parameters live. Never hardcode — always read from the source table.}

| Column | Description |
| :----- | :---------- |
| `{column}` | {description / how to parse} |

**Join key**: {how to match parameters to the components}

**Fallback**: {what to do when a parameter is missing for a period}

## Dos and Don'ts

**Do:**

- {Mandatory rule — e.g. apply the full canonical filter}
- {Read parameters from the source, use fallback, deduplicate}

**Don't:**

- {Anti-pattern — e.g. directly pooling the components}
- {Don't hardcode weights/parameters}

## Golden Queries

{One sentence on what the query computes.} The component CTE reproduces the pattern already documented in the related business entity; what is exclusive to this metric is {the weighting / official aggregation layer}.

```sql
WITH component AS (
    -- Component metric — same pattern as ../business_entities/{entity_slug}.md.
    SELECT
        {dimension},
        {component_expression} AS component_value
    FROM {schema}.{table}
    WHERE {canonical_filter}
    GROUP BY 1
)
SELECT
    {dimension},
    {official_expression} AS {metric_alias}
FROM component
GROUP BY 1
ORDER BY 1
```

## Superset Golden Assets

<!--
Optional. List Superset virtual datasets (and the materialized Trino/Databricks tables they
map to) that serve as the canonical starting point for this metric in Superset.

CI links both as reference assets on the Data Product Summary in DataHub — same pattern as
nps-fr: Trino `schema.table` pairs (e.g. materialized `sandbox.nps_fr`) AND Superset dataset
URNs in backticks. Omit this section when no Superset asset exists for this metric.
-->

- **{Asset Name}** — {one-sentence description}. Materialized in `{schema}.{table}` when applicable. URN: `urn:li:dataset:(urn:li:dataPlatform:superset,{id},PROD)`
```

### Section-by-section guidance

**Ownership:**
- First section after the title. Two required bold sub-groups, **Data Owner:** and **Data Steward:**, each with at least one `@quintoandar.com.br` email bullet (they may overlap).
- Ask the user for both in Step 1 if not already provided.
- Not folded into the DataHub Data Product description (see `EXCLUDE_HEADING_PATTERNS` in `generate_and_push_datahub_entities.py`) — it is routing metadata, not narrative content.

**Overview:**
- State what the metric is and why a naive calculation is wrong.
- Always flag product-scope restrictions in bold.
- Keep to 2–4 sentences — schema lives in the business entity.

**Related Business Entities:**
- Plain list of entity names (no paths, no descriptions). One bullet per entity.
- TARS uses this to navigate to the schema file before building SQL.

**MBR:**
- Optional. Include only when the metric feeds one or more Monthly Business Reviews; omit the section entirely otherwise.
- One bullet per MBR name (a metric may belong to several). Grain is the whole document — every metric here is treated as part of the listed MBR(s).
- Not folded into the DataHub Data Product description — CI syncs it to the `data_product.mbr` structured property (filterable in DataHub). It is routing metadata, not narrative content.

**Glossary and Synonyms:**
- Bullet list format. Include every alias analysts or stakeholders use to ask for this metric.
- Purpose: TARS routing — if a user says "NPS True", TARS needs to land here.

**Scope:**
- Be exhaustive on what is *excluded* — this is where the most common bugs come from.
- Include campaign purpose values, segment names, or product restrictions verbatim.

**Calculation:**
- Show the formula in a code block for clarity.
- If the formula is a weighted sum, define each weight and how it's sourced.
- The Canonical Filter subsection must list *every* mandatory field — not just the obvious one.
- The Warning in Canonical Filter must name the specific wrong result caused by under-filtering.

**Nuances:**
- Document every non-obvious parsing or join pattern (e.g., string-to-float cast for `'25%'`).
- Specify the fallback clearly: what table, what window function, what ordering.
- The column table should only include columns where the usage is non-obvious.

**Dos and Don'ts:**
- Do NOT repeat generic dos/don'ts from the business entity.
- Focus on traps specific to the official metric (formula-level, not schema-level).

**Golden Queries:**
- **One canonical query** that produces the official metric number.
- **Trino SQL dialect** — TARS runs on Trino. No Spark-only constructs (`QUALIFY`, `GROUP BY ALL`, `IFF`, 3-arg `DATEDIFF`, variant `col:key`).
- Reference the component CTE pattern from the business entity explicitly in a comment — do not re-teach it, just note where it comes from.
- Add only the layer exclusive to this metric: the weighting, fallback, dedup, and final aggregation.
- Validate all table and column names against governance metadata YAMLs or database MCP.

**Superset Golden Assets:**
- Lists Superset virtual datasets and the materialized Trino `` `schema.table` `` pairs they map to, linked as reference assets on the Data Product Summary in DataHub (nps-fr pattern).
- Include Superset URNs in backticks: `` `urn:li:dataset:(urn:li:dataPlatform:superset,{id},PROD)` ``.
- Include every `` `schema.table` `` and Superset URN in backticks so CI can extract them deterministically.
- Omit the section when the metric has no Trino table and no Superset asset.

---

## Step 4 — Register the metric in intro.md

Add the new metric to the "Available metric entities" list in `docs/llm_context/intro.md`:

```markdown
- `metric_entities/{metric_slug}.md` — {Official Metric Name}: {one-sentence description with key aliases}. Builds on `business_entities/{entity_slug}.md`.
```

---

## Step 5 — Add back-link in the related business entity

Open the related business entity file(s) in `docs/llm_context/business_entities/` and add or update a **"Related Metric Entities"** section (or a bullet to an existing one) pointing back to this metric:

```markdown
## Related Metric Entities

- [{Official Metric Name}](../metric_entities/{metric_slug}.md) — {one-sentence description}.
```

If the business entity already has a "Related Metric Entities" section, just add the new bullet without restructuring the file.

---

## Step 6 — Self-review checklist

Before presenting to the user, verify:

- [ ] File lives at `docs/llm_context/metric_entities/{metric_slug}.md` (lowercase snake_case)
- [ ] `## Ownership` is the first section after the title, with at least one `@quintoandar.com.br` email under **Data Owner** and one under **Data Steward**
- [ ] Overview states both what the metric is AND why the naive calculation is wrong
- [ ] Product-scope restriction is bolded (or absent if the metric is universal)
- [ ] Related Business Entities lists names only — no paths, no descriptions
- [ ] MBR section present with one bullet per MBR when the metric feeds an MBR — omitted entirely otherwise (no empty section, no placeholders)
- [ ] Scope Excluded section covers every known non-qualifying segment/campaign
- [ ] Canonical Filter lists ALL mandatory predicates, not just the primary one
- [ ] Warning in Canonical Filter names the specific incorrect result from under-filtering
- [ ] Nuances documents every non-obvious parsing pattern (string casts, window functions)
- [ ] Dos and Don'ts are specific to this metric's formula — no generic schema-level advice
- [ ] Golden Query uses **Trino SQL dialect** (no `QUALIFY`, `GROUP BY ALL`, `IFF`, 3-arg `DATEDIFF`, variant `col:key`)
- [ ] Golden Query validates column names against governance YAMLs and Trino
- [ ] Golden Query references the business entity component pattern in a comment instead of duplicating it
- [ ] Metric registered in `docs/llm_context/intro.md` under "Available metric entities"
- [ ] Back-link added to "Related Metric Entities" in the related business entity file(s)
- [ ] Superset Golden Assets omitted if no canonical asset; Superset URNs and Trino tables in backticks when present
