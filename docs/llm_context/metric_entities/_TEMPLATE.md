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
  • After creating: register the file under "Available metric entities" in
    ../intro.md, and add a "Related Metric Entities" back-link from the related
    business entity(ies).
  • Golden Query must use Trino SQL dialect (TARS runs on Trino). No Spark-only
    constructs (QUALIFY, GROUP BY ALL, IFF, 3-arg DATEDIFF, variant `col:key`).
-->

## Overview

**{Name}** is {one-sentence definition}. {How it differs from the naive/component calculation / why the business rule exists}.

**{Product-scope restriction, if any — e.g. "Exists exclusively for For Rent."}**

## Related Business Entities

<!--
Plain list of the business entity NAMES this metric draws its schema from — no
paths, no descriptions (intro.md explains the cross-link sections and where to
find each entity). One bullet per related entity.
-->

- {Business Entity Name}

## DataHub Catalog

<!--
URNs for the DataHub data products this metric links to. TARS uses these to
call get_entities() and fetch schema, glossary, and golden queries from the catalog.
Include this metric's own data product URN if one exists in DataHub.
-->

- **This metric's data product**: `urn:li:dataProduct:{metric-id}` <!-- remove if no metric data product exists yet -->
- **Upstream business entity data product**: `urn:li:dataProduct:{entity-id}`

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
Optional. List Superset datasets or dashboards that serve as the canonical starting point for
data manipulation on this metric in Superset. Include the asset name and a short note on its
role. Omit this section if no golden Superset asset exists for this metric.
-->

- **{Asset Name}** — {one-sentence description of what this asset is and when to use it as a base.}
