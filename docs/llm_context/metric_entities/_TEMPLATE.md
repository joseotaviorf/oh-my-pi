# {Official Metric Name}

<!--
WRITING GUIDE — delete this block before committing.

Audience: TARS (text-to-SQL AI agent) and human analysts.
Goal: define ONE official, named metric — its exact calculation, scope, canonical
      filter, and weight/parameter sources — so TARS reproduces the source-of-truth
      number instead of a naive approximation.

ROLE CONTRACT (this is what makes a metric entity different from a business entity):
  • A metric entity documents the OFFICIAL METRIC. The schema (tables, columns,
    grain, joins) and the component/generic metric live in the linked
    business entity under ../business_entities/. NEVER re-document columns or
    re-teach the component calculation here — LINK to the business entity instead.
  • Keep this file thin on schema, thick on calculation: overview, scope,
    exact formula, canonical filter, parameter/weight sources, dos/don'ts, and
    the single golden query that produces the official number.
  • Its Calculation / Canonical Filter / Dos and Don'ts OVERRIDE generic logic in the
    business entity when both touch the same domain.

Rules:
  • File name: lowercase_snake_case.md (e.g. nps_fr.md, gmv_fs.md).
  • After creating: add a "Related Metric Entities" back-link from the related
    business entity(ies).
  • **Product scope (RENT / SALE):** state explicitly in **Scope** and whenever citing
    source tables — use **just rent** / **just sale** / **both** for table context (not
    “RENT only” / “SALE only” for table scope). TARS must not classify a table as rent
    or sale unless documented in this metric entity or the linked business entity.
  • Golden Query must use Trino SQL dialect (TARS runs on Trino). No Spark-only
    constructs (QUALIFY, GROUP BY ALL, IFF, 3-arg DATEDIFF, variant `col:key`).
  • Optional sections: MBR, Targets and OKRs (Budget and/or OKR lookup — see section
    below; Budget = annual commitment fixed for the fiscal year; OKR = period
    challenge that may change across quarters/semesters), Superset Golden Assets.
  • Required section: Catalog — every named metric defined in this document, each
    classified as OKR or Health Metric.
-->

## Ownership

<!--
Data Owner: accountable for the business definition and approves changes (usually a
manager/lead). Data Steward: maintains this document day-to-day and is the first point
of contact for questions. At least one email is required in EACH category (they may
overlap). Not folded into the DataHub Data Product description (see
EXCLUDE_HEADING_PATTERNS in generate_and_push_datahub_entities.py) — it is routing
metadata, not narrative content.
-->

**Data Owner:**
- {data_owner_email@quintoandar.com.br}

**Data Steward:**
- {data_steward_email@quintoandar.com.br}

## Overview

**{Name}** is {one-sentence definition}. {How it differs from the naive/component calculation / why the business rule exists}.

**{Product-scope restriction, if any — e.g. "Exists exclusively for For Rent."}**

## Related Business Entities

<!--
Plain list of the business entity NAMES this metric draws its schema from — no
paths, no descriptions. Business entities live in ../business_entities/, metric
entities in ../metric_entities/ (one file per entity). Add back-links in the
related business entity's "Related Metric Entities" section. One bullet per
related entity.
-->

- {Business Entity Name}

## Catalog

<!--
Required — the inventory of every OFFICIAL metric this document defines. One row per
metric, using the exact official name analysts see (the same name used in Overview /
Calculation / Glossary). A single-metric document has exactly one row; a metric family
has one row per member.

Type classifies how the metric is used by the business:
  • OKR           — the metric carries a period goal (quarter/semester) and is tracked
                    as a company/area objective.
  • Health Metric — the metric is monitored to watch operational health; it has no
                    OKR goal of its own (it may still be a component of one).

Not folded into the DataHub Data Product description (see EXCLUDE_HEADING_PATTERNS in
generate_and_push_datahub_entities.py) — CI syncs the names to the
`data_product.metrics` structured property and the types to `data_product.metric_type`
(both multi-valued and filterable in DataHub). It is routing metadata, not narrative
content.
-->

| Metric | Type |
| :---- | :---- |
| {Official Metric Name} | {OKR \| Health Metric} |

## MBR

<!--
Optional — include ONLY when this metric participates in one or more Monthly Business
Reviews (MBRs). Grain is the Data Product: this flag marks the WHOLE document, so every
metric defined here is considered part of the listed MBR(s). Repeat the Name/Category
pair once per MBR (a metric may feed several). Omit the entire section if the metric is
not part of any MBR.

Name marks WHICH MBR the document feeds; Category marks the block the metric sits in
inside that MBR's agenda. Name is required once the section is present; Category is
optional — drop its line entirely when the block is unknown, rather than leaving the
placeholder behind. Not folded into the DataHub Data Product description (see
EXCLUDE_HEADING_PATTERNS in generate_and_push_datahub_entities.py) — CI syncs Name to
the `data_product.mbr` structured property and Category to `data_product.mbr_category`
(both filterable in DataHub), it is routing metadata, not narrative content.
-->

**Name** {MBR Name}
**Category** {category}

## Glossary and Synonyms

<!-- Names and terms analysts/stakeholders use to ASK for this metric. TARS uses these to route. -->

- **{term}**, **{synonym}**, **{official name}** → this metric

## Scope

**Included**: {journeys, segments, audiences}

**Excluded**: {what does NOT count — test campaigns, out-of-scope segments, etc.}

## Calculation

<!-- The official formula. If there is non-trivial pooling/weighting/aggregation, explain WHY the
     naive path is wrong. This section is the source of truth and overrides the business entity. -->

{Explain the error of the naive path, if applicable.}

The correct calculation is:

```
{Metric} = {formula, e.g. weighted sum of components}
```

where {definition of each term / component}.

### Canonical Filter

<!-- The EXACT set of filters that defines the metric's universe. List the mandatory fields and
     warn about the common mistake of under-filtering. -->

Apply on `{table/dim}`:

```sql
{field_1} = '{value}'
AND {field_2} = '{value}'
```

**Warning**: {common mistake — e.g. filtering only on one field includes segments that do not compose the official metric}.

### Nuances

<!-- Weight/parameter sources (GSheets, etc.), fallback, deduplication, specific join keys. -->

{Where the weights/parameters live. Never hardcode — always read from the source.}

| Column | Description |
| :---- | :---- |
| `{column}` | {description / how to parse} |

**Join key**: {how to match parameters to the components}

**Fallback**: {what to do when a parameter is missing for a period}

## Dos and Don'ts

<!-- Traps SPECIFIC to the official metric. Do not repeat generic dos/don'ts from the business entity. -->

**Do:**

- {Mandatory rule — e.g. apply the full canonical filter}
- {Read parameters from the source, use fallback, deduplicate}

**Don't:**

- {Anti-pattern — e.g. directly pooling the components}
- {Don't hardcode weights/parameters}
- Don't state that a source table is **just rent** or **just sale** unless **Scope** or the linked business entity **explicitly** documents that scope for that table. Do not use **“RENT only” / “SALE only”** for table scope.

## Targets and OKRs

<!--
Optional — include ONLY when this metric has an official Budget and/or OKR lookup path.
Omit the entire section when neither exists.

Terminology (both optional within this section):
  • Budget (Target) — annual commitment set at year start; fixed for the fiscal year.
  • OKR — period challenge (quarter or semester), informed by trend indicators; may
    change across periods within the year.

Document HOW to fetch each value (source table, filter key, aliases, scope caveats
when comparing actuals vs Budget/OKR). Do NOT duplicate the calculation formula.
Folded INTO the DataHub product_description (unlike MBR / Golden Queries).
-->

**Budget (Target)** — {one line: what the annual commitment represents for this metric, or omit this block}.

- **Source table:** `{schema}.{table}`
- **Filter key / metric name:** `{exact name in source}`
- **Aliases / search terms:** {PT-BR: orçamento, budget, target, …}
- **Caveat:** {scope mismatch vs actuals, if any}

**OKR** — {one line: what the period goal represents, or omit this block}.

- **Source table:** `{schema}.{table}` (may differ from Budget)
- **Filter key / metric name:** `{exact name in source}`
- **Period grain:** {quarter / semester / month — how the OKR is keyed in the source}
- **Aliases / search terms:** {PT-BR: meta, OKR, …}
- **Caveat:** {scope mismatch vs actuals, if any}

## Golden Queries

<!-- The single canonical query that PRODUCES the official metric. Reuse the component pattern from
     the business entity (reference it) and add ONLY the layer exclusive to this metric. Trino dialect. -->

{One sentence on what the query computes.} The component CTE reproduces the pattern already documented in the related business entity; what is exclusive to this metric is {the weighting / official aggregation layer}.

```sql
WITH component AS (
    -- Component metric — same pattern as the related business entity.
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
Optional. List Superset virtual datasets (and materialized Trino/Databricks tables they map to)
that serve as the canonical starting point for this metric in Superset.

CI links both as reference assets on the Data Product Summary in DataHub — same pattern as
nps-fr: Trino ``schema.table`` pairs (e.g. materialized ``sandbox.nps_fr``) AND Superset
dataset URNs in backticks. Omit this section when no Superset asset exists for this metric.
-->

- **{Asset Name}** — {one-sentence description}. Materialized in `{schema}.{table}` when applicable. URN: `urn:li:dataset:(urn:li:dataPlatform:superset,{id},PROD)`
