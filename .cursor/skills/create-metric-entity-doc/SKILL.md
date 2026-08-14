---
name: create-metric-entity-doc
description: Create a new metric entity documentation file in docs/llm_context/metric_entities/. Metric entity docs are thin on schema and thick on calculation — they define ONE official, named metric with its exact formula, scope, canonical filter, weight/parameter sources, and the single canonical query that reproduces the source-of-truth number. Use when the user asks to document a new official metric, add a metric entity, or define how the TARS plugin should compute an official indicator.
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
10. **Superset golden assets** — the reference assets for this metric: canonical Superset virtual datasets and/or the materialized Trino/Databricks `schema.table` tables they map to (e.g. `sandbox.nps_fr`). These are linked as reference assets on the DataHub Data Product Summary. Optional section in the final doc — omit `## Superset Golden Assets` when no asset exists.
11. **Ownership emails** — at least one **Data Owner** (accountable for the business definition, usually a manager/lead) and at least one **Data Steward** (`@quintoandar.com.br`/`@quintoandar.com`, maintains this document day-to-day; defaults to the requester if not otherwise specified). The two roles may share the same email.
12. **MBR membership** — does this metric feed one or more Monthly Business Reviews (MBRs)? If so, which one(s)? Optional section — omit if the metric is not part of any MBR. A metric may belong to several MBRs.
13. **Budget / OKR** — optional. Ask separately whether the metric has an official **Budget (Target)** (annual commitment, fixed for the fiscal year) and/or **OKR** (period challenge — quarter or semester — that may change across the year). For each that exists: source table, filter key / metric name in source, period grain (OKR only), PT-BR aliases, and scope caveats when comparing actuals vs Budget/OKR.

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

Create `docs/llm_context/metric_entities/{metric_slug}.md` following the template below exactly. Keep the file concise: thick on calculation, thin on schema.

### Required sections (mandatory)

**Every metric entity doc MUST include every `##` section from the template below, in order, with real content** — no omitted headings, no placeholder text (`TBD`, `{...}`), no empty sections.

**Three sections are optional** and may be omitted entirely (no empty heading, no placeholders):

- **`## MBR`** — omit when the metric does not feed any Monthly Business Review, always ask the user about it
- **`## Targets and OKRs`** — omit when the metric has no official Budget or OKR source, always ask the user about it
- **`## Superset Golden Assets`** — omit when the metric has no canonical Superset dataset or Trino table to link, always ask the user about it

| Section | Required |
| :------ | :------- |
| `## Ownership` | Yes — at least one email under **Data Owner** and one under **Data Steward** |
| `## Overview` | Yes |
| `## Related Business Entities` | Yes — at least one bullet |
| `## Catalog` | Yes — one row per official metric defined in this document, each classified as **OKR** or **Health Metric**. CI (`_validate_catalog_types` in `generate_and_push_datahub_entities.py`) hard-blocks publishing when a catalog row has a missing/invalid type. |
| `## MBR` | No — omit when the metric feeds no MBR, but confirm with the user. When present, **Name** is required and **Category** is optional (drop its line when the block is unknown) |
| `## Glossary and Synonyms` | Yes — at least one bullet |
| `## Scope` | Yes — both **Included** and **Excluded** |
| `## Calculation` | Yes — includes `### Canonical Filter` and `### Nuances` |
| `## Dos and Don'ts` | Yes — both **Do** and **Don't** lists |
| `## Targets and OKRs` | No — omit when the metric has no official Budget or OKR source, but confirm with the user |
| `## Golden Queries` | Yes — at least one Trino query |
| `## Superset Golden Assets` | No — omit when no canonical asset exists, but confirm with the user |

**Do not skip or reorder the required sections**. If a required section has no applicable content beyond the mandatory minimum (e.g. no product-scope restriction in Overview), state that explicitly in prose rather than deleting the section.

### Template structure

Full section order (optional sections shown in place — omit them entirely when not applicable):

```
# {Official Metric Name}
## Ownership                         [required]
## Overview                          [required]
## Related Business Entities         [required]
## Catalog                           [required]
## MBR                               [optional]
## Glossary and Synonyms              [required]
## Scope                              [required]
## Calculation                        [required]
  ### Canonical Filter
  ### Nuances
## Dos and Don'ts                    [required]
## Targets and OKRs                   [optional]
## Golden Queries                     [required]
## Superset Golden Assets             [optional]
```

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

## Catalog

<!-- [REQUIRED] One row per official metric this document defines. Type: OKR (carries a period goal) or Health Metric (monitored, no goal of its own). -->

| Metric | Type |
| :---- | :---- |
| {Official Metric Name} | {OKR \| Health Metric} |

## MBR

<!-- [OPTIONAL] One Name/Category pair per MBR this metric feeds. Omit this entire section when the metric feeds no MBR. -->

**Name** {MBR Name}
**Category** {category}

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

## Targets and OKRs

<!--
Optional — include ONLY when this metric has an official Budget and/or OKR lookup path.
Omit the entire section when neither exists.

Terminology (both optional within this section):
  • Budget (Target) — annual commitment set at year start; fixed for the fiscal year.
  • OKR — period challenge (quarter or semester), informed by trend indicators; may
    change across periods within the year.
-->

**Budget (Target)** — {one line: what the annual commitment represents, or omit this block}.

- **Source table:** `{schema}.{table}`
- **Filter key / metric name:** `{exact name in source}`
- **Aliases / search terms:** {PT-BR: orçamento, budget, target, …}
- **Caveat:** {scope mismatch vs actuals, if any}

**OKR** — {one line: what the period goal represents, or omit this block}.

- **Source table:** `{schema}.{table}` (may differ from Budget)
- **Filter key / metric name:** `{exact name in source}`
- **Period grain:** {quarter / semester / month}
- **Aliases / search terms:** {PT-BR: meta, OKR, …}
- **Caveat:** {scope mismatch vs actuals, if any}

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

**Catalog:**
- Required. One table row per official metric the document defines — a single-metric doc has one row; a metric family has one row per member.
- Use the exact official metric name analysts see, matching the name used in Overview / Calculation / Glossary.
- `Type` is `OKR` when the metric carries a period goal tracked as an objective, or `Health Metric` when it is monitored for operational health without a goal of its own (it may still be a component of an OKR).
- Not folded into the DataHub Data Product description — CI syncs the names to `data_product.metrics` and the types to `data_product.metric_type` (both filterable in DataHub).

**MBR:**
- Optional, but always confirm with the user. Include only when the metric feeds one or more Monthly Business Reviews; omit the section entirely otherwise.
- One `**Name**` / `**Category**` pair per MBR (a metric may belong to several). Grain is the whole document — every metric here is treated as part of the listed MBR(s).
- `Name` identifies the MBR; `Category` is the block the metric sits in inside that MBR's agenda.
- Not folded into the DataHub Data Product description — CI syncs `Name` to the `data_product.mbr` structured property and `Category` to `data_product.mbr_category` (both filterable in DataHub). It is routing metadata, not narrative content.

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

**Targets and OKRs:**
- Optional. Omit the entire section when the metric has no official Budget or OKR source.
- **Budget (Target)** = annual commitment fixed for the fiscal year; **OKR** = period challenge (quarter/semester) that may change across the year. Document only the sub-blocks that apply.
- For each sub-block: source table, filter key, aliases, scope caveats — never duplicate the Calculation formula.
- Folded into the DataHub `product_description` (not excluded like MBR or Golden Queries).

**Golden Queries:**
- **Hard cap: never write more than 10 golden queries**, regardless of how many
  component/reconciliation queries Step 2 surfaces. If more than 10 are warranted, keep
  the 10 most valuable/representative and tell the user which ones were deferred (they
  are candidates for a follow-up doc). This is enforced at generation time — it's a
  different gate from the token-based review in Step 3b, which still runs afterward.
- **One canonical query** that produces the official metric number.
- **Trino SQL dialect** — TARS runs on Trino. No Spark-only constructs (`QUALIFY`, `GROUP BY ALL`, `IFF`, 3-arg `DATEDIFF`, variant `col:key`).
- Reference the component CTE pattern from the business entity explicitly in a comment — do not re-teach it, just note where it comes from.
- Add only the layer exclusive to this metric: the weighting, fallback, dedup, and final aggregation.
- Validate all table and column names against governance metadata YAMLs or database MCP.

**Superset Golden Assets:**
- Optional, but always confirm with the user; omit the section when the metric has no Trino table and no Superset asset.
- Lists Superset virtual datasets and the materialized Trino `` `schema.table` `` pairs they map to, linked as reference assets on the Data Product Summary in DataHub (nps-fr pattern).
- Include Superset URNs in backticks: `` `urn:li:dataset:(urn:li:dataPlatform:superset,{id},PROD)` ``.
- Include every `` `schema.table` `` and Superset URN in backticks so CI can extract them deterministically.

---

## Step 3b — DataHub token-overflow risk check (mandatory)

`## Golden Queries` is converted to DataHub YAML by a single LLM call with a fixed
`max_tokens` ceiling (`LITELLM_MAX_TOKENS`, default 16000, in
`packages/bietlejuice-compiler/scripts/ci_cd/generate_and_push_datahub_entities.py`).
A metric with many and/or very large SQL golden queries can exceed that ceiling and
get a truncated response — CI now hard-fails on a declared-vs-generated mismatch
(see the Cases Perspective incident: 9 golden queries declared, only 2 published),
but catch the risk here, before the PR even exists.

Run the same credential-free counting logic CI uses, against the file you just wrote —
measuring the **Golden Queries section** specifically (not the whole file: prose sections
like Overview/Scope don't feed the same LLM call and would make the signal noisy):

```bash
uv run --directory packages/bietlejuice-compiler python -c "
import sys; sys.path.insert(0, 'scripts/ci_cd')
import generate_and_push_datahub_entities as g
from pathlib import Path
md_path = Path('../../docs/llm_context/metric_entities/{metric_slug}.md')
lines = md_path.read_text().splitlines()
in_section, section_bytes = False, 0
for line in lines:
    if g._GOLDEN_QUERY_SINGULAR_HEADING_RE.match(line) or g._GOLDEN_QUERY_SECTION_HEADING_RE.match(line):
        in_section = True; continue
    if in_section and line.startswith('## '):
        in_section = False; continue
    if in_section:
        section_bytes += len(line) + 1
print('golden_queries=', g._count_expected_golden_queries(md_path))
print('golden_queries_section_bytes=', section_bytes)
"
```

Reference point: the entity that actually truncated, Cases Perspective (a metric doc), was
9 golden queries at ~34KB of section text at the time of the incident. A typical metric doc
has exactly one canonical query and is nowhere near this (single digits of KB) — treat this
check as most relevant when a metric legitimately needs several component/reconciliation
queries. Don't calibrate against byte counts of other specific existing docs — they get
edited over time and any number pinned here would go stale.

Note this check is now a secondary defense, not the primary one: `_inject_golden_query_sqls`
in `generate_and_push_datahub_entities.py` extracts golden-query SQL directly from the
Markdown and injects it into the YAML deterministically after LLM generation — the LLM only
emits a placeholder for `sql:`, not the SQL text itself. This removes most of the original
truncation vector (reproducing large SQL blocks). Residual risk comes from what the LLM
still authors: `name`/`description`/`subjects` per golden query, so
`golden_queries_section_bytes` is now a rougher proxy than before, but still worth checking
when a metric legitimately has several component queries.

Flag the metric as **at risk of LLM truncation** during the `push-datahub-business-context`
Woodpecker step when any of these hold:
- `golden_queries_section_bytes` > ~8,000 (roughly 2,000 tokens) — this is the primary,
  token-based signal and applies regardless of query count
- `golden_queries` > 10 — should never happen when authored through this skill (Step 3
  enforces a hard cap of 10); if you see this on review, the doc was likely hand-edited
  after generation
- the golden query's ` ```sql ` block is unusually large (roughly 40+ lines)

When at risk, say so explicitly in your final response to the user and recommend one of:
- Raising `LITELLM_MAX_TOKENS` for the CI run that will publish this metric, or
- Splitting the Golden Queries section (fewer queries per PR / a follow-up PR for the rest).

This is a **heads-up, not a hard blocker** — CI already fails hard on an actual
declared-vs-generated mismatch, so don't refuse to finish the doc solely on this signal;
just make sure the user knows before opening the PR.

---

## Step 4 — Add back-link in the related business entity

Open the related business entity file(s) in `docs/llm_context/business_entities/` and add or update a **"Related Metric Entities"** section (or a bullet to an existing one) pointing back to this metric:

```markdown
## Related Metric Entities

- [{Official Metric Name}](../metric_entities/{metric_slug}.md) — {one-sentence description}.
```

If the business entity already has a "Related Metric Entities" section, just add the new bullet without restructuring the file.

---

## Step 5 — Self-review checklist

Before presenting to the user, verify:

- [ ] File lives at `docs/llm_context/metric_entities/{metric_slug}.md` (lowercase snake_case)
- [ ] All mandatory `##` sections present (Ownership → Golden Queries), in template order — only `## MBR`, `## Targets and OKRs` and `## Superset Golden Assets` may be absent
- [ ] `## Ownership` is the first section after the title, with at least one `@quintoandar.com.br` email under **Data Owner** and one under **Data Steward**
- [ ] Overview states both what the metric is AND why the naive calculation is wrong
- [ ] Product-scope restriction is bolded (or absent if the metric is universal)
- [ ] Related Business Entities lists names only — no paths, no descriptions
- [ ] Catalog has one row per official metric defined in the document, each classified as `OKR` or `Health Metric` — CI hard-blocks on a missing/invalid type
- [ ] MBR section present with one bullet per MBR when the metric feeds an MBR — omitted entirely otherwise (no empty section, no placeholders)
- [ ] Scope Excluded section covers every known non-qualifying segment/campaign
- [ ] Canonical Filter lists ALL mandatory predicates, not just the primary one
- [ ] Warning in Canonical Filter names the specific incorrect result from under-filtering
- [ ] Nuances documents every non-obvious parsing pattern (string casts, window functions)
- [ ] Dos and Don'ts are specific to this metric's formula — no generic schema-level advice
- [ ] Golden Query uses **Trino SQL dialect** (no `QUALIFY`, `GROUP BY ALL`, `IFF`, 3-arg `DATEDIFF`, variant `col:key`)
- [ ] Golden Query validates column names against governance YAMLs and Trino
- [ ] DataHub token-overflow risk check run (Step 3b); user warned if at risk
- [ ] Golden Query references the business entity component pattern in a comment instead of duplicating it
- [ ] Back-link added to "Related Metric Entities" in the related business entity file(s)
- [ ] Targets and OKRs omitted when no Budget/OKR source; Budget and OKR sub-blocks documented separately when both exist
- [ ] Superset Golden Assets omitted if no canonical asset; Superset URNs and Trino tables in backticks when present

---

<!-- LUIGI:SELF-SERVICE:BEGIN -->

## Self-Service Submissions via Zordon (Luigi)

> **This block is the single source Zordon/Luigi reads to guide a self-service submission**,
> so it is written for that consumer and is self-contained. Steps 1–6 above — asking the user, codebase research, Explore
> subagents, Trino MCP, the `uv` byte-count check, the business-entity
> back-link — are for an **engineer or Cursor agent editing the repo directly** and do **not**
> apply to a chat submission. This block only restates the *content contract* the finished file
> must satisfy. If it ever disagrees with the sections above, **the sections above win** — keep
> it in lockstep with them.

**How the flow actually works.** A non-technical user uploads a finished metric-entity `.md` in
Google Chat. Zordon validates it in the conversation and, if it passes, opens a review PR on
`bi-etl-ejuice`; a human data engineer reviews it, and merging to `master` publishes it to DataHub.
Zordon never researches the codebase or writes the doc for the user — it only checks the uploaded
file against the contract below and tells the user, in plain language, what to fix and re-upload.

**Filename — Zordon derives it, the user does not choose it.** It comes from the official metric
name: lowercased, accents stripped, then every run of non-alphanumeric characters collapsed to a
single `_` (e.g. `Ticket Rate Front - Pós Contrato` → `ticket_rate_front_pos_contrato.md`). A name
that collides with an already-published metric is surfaced by Zordon's own duplicate/existing-entity
check (below), not asked about up front.

**Language.** The prose (headings + body) must be predominantly **English**. Portuguese is expected
and must NOT be flagged in: `## Glossary and Synonyms` entries, short parenthetical glosses of a
local term (e.g. "condominium bills (condomínio)"), and any code, SQL, identifiers, emails, or URLs.

**No template leftovers.** Reject any unfilled placeholder (text wrapped in `{...}`), any `TBD`, and any leftover `WRITING GUIDE` comment block.

### Required sections — the automated gates block the PR if any is missing or empty

Both the CI check (in `bi-etl-ejuice`) and Zordon's pre-check block the PR when a required section is **missing or empty**. Machine-checkable specifics include Ownership emails, **Catalog** rows with Type `OKR` or `Health Metric`, at least one **Related Business Entities** bullet, **`### Canonical Filter`** and **`### Nuances`** under Calculation, and at least one Trino ``sql`` Golden Query block (no Spark-only constructs). Reject empty optional headings — omit optional sections entirely when they do not apply.

Scope **Included/Excluded** lists and both a **Do** and a **Don't** describe what a **good** section looks like: CI may surface them as **non-blocking warnings**; the reviewer confirms them in PR review.

| Section | What it must contain |
| :------ | :------------------- |
| `# {Official Metric Name}` | The H1 title: the metric's full official name, spelled out (not an acronym). |
| `## Ownership` | **Data Owner:** at least one `@quintoandar.com.br`/`@quintoandar.com` email, **and** **Data Steward:** at least one such email. The two roles may be the same person. |
| `## Overview` | 2–4 sentences: what the metric is and why a naive/component calculation is wrong. Product-scope restriction in **bold** if it exists. |
| `## Related Business Entities` | At least one bullet naming an existing business entity (names only — no paths, no descriptions). |
| `## Catalog` | One row per official metric defined in the document (exact name used elsewhere in the doc), each with a `Type` of `OKR` or `Health Metric`. |
| `## Glossary and Synonyms` | At least one bullet mapping every alias/synonym a user might say to this metric. |
| `## Scope` | Both an **Included** and an **Excluded** list (recommended — CI warns if either is missing). |
| `## Calculation` | The exact formula, plus **`### Canonical Filter`** (every mandatory predicate) and **`### Nuances`**. |
| `## Dos and Don'ts` | Both a **Do** and a **Don't** list recommended — specific to this metric's formula. |
| `## Golden Queries` | At least one Trino SQL block (a triple-backtick `sql` fence). No Spark-only constructs: `QUALIFY`, `GROUP BY ALL`, `IFF`, 3-argument `DATEDIFF`, or `col:key` variant access. |

### Optional sections — never required; include only when they apply

- `## MBR` — one bullet per Monthly Business Review the metric feeds; omit the whole section otherwise.
- `## Targets and OKRs` — the metric's official Budget (annual target) and/or OKR (period goal) lookup path; omit the whole section otherwise.
- `## Superset Golden Assets` — canonical Superset datasets and the `` `schema.table` `` pairs they map to; omit the whole section otherwise.

### What Zordon must NOT ask the user

- **The owner's / steward's email** — it is already required inside `## Ownership`, so Zordon reads
  it straight from the uploaded file instead of asking again.
- **Anything that needs repo access** (which tables exist, whether a slug is already taken, whether
  this duplicates an existing metric) — Zordon checks that itself against `bi-etl-ejuice` and only
  speaks up when it actually finds a conflict or a likely duplicate.

<!-- LUIGI:SELF-SERVICE:END -->

