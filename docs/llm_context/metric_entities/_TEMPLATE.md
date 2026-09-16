# {Metric Entity Name}

<!--
WRITING GUIDE — delete this block before committing.

Audience: TARS (text-to-SQL AI agent) and human analysts.
Goal: define a metric entity — a group of one or more related official metrics — so
      TARS reproduces the source-of-truth number for each instead of a naive
      approximation.

ROLE CONTRACT (this is what makes a metric entity different from a domain entity):
  • A metric entity documents OFFICIAL METRICS. The schema (tables, columns, grain,
    joins) lives in the linked domain entity under ../domain_entities/. NEVER
    re-document columns here — LINK to the domain entity instead.
  • Keep this file thin on schema, thick on what each metric is and how to query it.

Rules:
  • File name: lowercase_snake_case.md (e.g. nps_fr.md, gmv_fs.md).
  • A single document holds 1–10 related metrics under ## Metrics — one ### {Metric
    Name} subsection each. Split into a second metric entity past 10.
  • Each metric's Golden Query must be valid Trino SQL (TARS runs on Trino) AND run
    unchanged on EMR Spark 3.5, because the same query seeds the materialized metric
    table. Stay in the intersection of the two dialects:
      – No Spark-only constructs: QUALIFY, GROUP BY ALL, IFF, 3-arg DATEDIFF,
        variant `col:key`. These are blocking errors.
      – Avoid Trino-only functions: date_parse, parse_datetime, format_datetime,
        strpos, arbitrary, approx_distinct, json_extract(_scalar), map_agg,
        at_timezone, to_unixtime, url_extract_*, try(), UNNEST, WITH ORDINALITY,
        and date_diff('unit', a, b). CI warns on these; prefer the portable spelling
        (to_timestamp, date_format, instr, any_value, approx_count_distinct,
        get_json_object, …).
      – Watch array indexing: Trino is 1-based, Spark is 0-based. Both run; only one
        is right.
  • Optional top-level sections: Related Domain Entities (inferred at authoring time),
    Targets and OKRs. Optional per-metric headings: MBR, Category. Omit any optional
    heading entirely when it does not apply — an empty heading is invalid.
-->

## Ownership

<!--
Data Owner: accountable for the business definition and approves changes (usually a
manager/lead). Data Steward: maintains this document day-to-day and is the first point
of contact for questions. Metric docs require at least one email in EACH category (they
may overlap). Routing metadata, not narrative content.
-->

**Data Owner:**
- {data_owner_email@quintoandar.com.br}

**Data Steward:**
- {data_steward_email@quintoandar.com.br}

## Description

<!-- 2–4 sentences: what this group of metrics measures, what it means, and why the
     business tracks it. Bold any product-scope restriction that applies to the whole
     entity. Per-metric nuances go in each metric's #### Description below. -->

**{Metric entity name}** groups {what these metrics measure and why the business tracks them}. {How they relate to each other.}

**{Entity-wide product-scope restriction, if any — e.g. "Exists exclusively for For Rent."}**

## Domain

<!--
Required — the metadata domain that owns these metrics. Must match the allowlist
exactly (it is written verbatim into the generated metric metadata, where CI accepts
nothing else): Agents, Cross, Data Ops & Governance, Data Life Cycle, Fintech,
For Rent, For Sale, Growth, International, Journey Optimizer, MLOps, People, QCX, Rede,
Support and Services, Tech Platform, Data Platform, Conversational XP, DS Pricing,
Atlas DB, Broker XP, House and Listing.
-->

{Domain}

## Related Domain Entities

<!--
Optional — inferred from the catalog at authoring time, not asked of the author. Plain
list of the domain entity NAMES these metrics draw their schema from — no paths, no
descriptions. Omit the whole section when no related domain entity is found.
-->

- {Domain Entity Name}

## Targets and OKRs

<!--
Optional — include ONLY when at least one metric has an official Budget and/or OKR
that is QUERYABLE IN PRODUCTION. Omit the whole section when neither exists.

Terminology:
  • Budget (Target) — annual commitment set at year start; fixed for the fiscal year.
  • OKR — period challenge (quarter or semester); may change across periods.

Document HOW to fetch each value (source table, filter key, period grain, aliases).
Name which metric each target belongs to when the entity has several.

NEVER write the numbers themselves. A transcribed period list ("Oct: 27; Nov: 27.5")
is stale the day the target is revised, and no pipeline can refresh it — this section
says WHERE the number lives, not what it is today.

Target exists but lives only outside production (a spreadsheet, a slide)? Omit the
section. Publish the targets via Luigi into a gsheet ingested by this repo, then come
back and add the lookup path. A blank section is recoverable; a hardcoded one rots.
-->

**{Metric Name} — OKR** — {one line: what the period goal represents}.

- **Source table:** `{schema}.{table}`
- **Filter key / metric name:** `{exact name in source}`
- **Period grain:** {quarter / semester / month}

## Metrics

<!--
Required — one ### {Metric Name} subsection per official metric (1–10 total). Repeat
the whole ### block per metric, keeping the heading order below.

Required per metric: Slug, Description, Also Known As, Rules, Type, Direction, Grain,
Is Additive, Golden Query. Optional: MBR, Category.

Two headings are still accepted when a document carries them, `Business Stage` and
`Acronym`, but they are not part of this contract and no flow emits them. Both feed
metric-layer columns that are optional there and that the future generator leaves blank
on purpose: neither has a reader, and deriving a short form from `Also Known As` is how
the current registry ended up with 43% of its acronyms holding the metric name instead.
An abbreviation the business really uses is an alias — it belongs in Also Known As.
-->

### {Metric Name A}

#### Slug

<!-- Required — snake_case, unique in this document, and FROZEN once chosen. It is the
     stable key between this metric and the table that will be materialized from it, so
     it must survive a rename of the display name above. Do not "improve" it later. -->

{metric_name_a}

#### Description

<!-- What this metric measures and how it differs from the naive/component calculation.
     Bold any per-metric scope restriction. -->

**{Metric Name A}** is {one-sentence definition}. {How it differs from the naive/component calculation.}

#### Also Known As

<!-- Required — the PT-BR and internal names stakeholders use when they ask for THIS
     metric; TARS routes on them. Nested here, the owning metric is structural, so a
     plain bullet is enough and no arrow is needed.

     Use the arrow only for a NEAR-MISS: a name that sounds like this metric but means
     something else. Recording it here is what stops TARS from answering the closest
     match instead of the right one. -->

- **{term}**, **{synonym}**
- **{near-miss term}** → near-miss — {what it actually refers to}, not this metric

#### Rules

<!--
Required — everything needed to reproduce the official number rather than a plausible
approximation. This is the guard-rail against under-filtering, which is the single most
common way this metric gets computed wrong. Cover, when they apply:
  • Canonical filter — the exact WHERE that defines the official population.
  • The common mistake — which filter people forget, and what it inflates/deflates.
  • Parameters and weights — WHERE they are read from (table/column). Never hardcode a
    weight or threshold here; point at the source so the value stays correct over time.
  • Fallback — what to do when a parameter is missing for a period.
  • Deduplication — the grain that makes a row unique, and how duplicates are resolved.
-->

- **Canonical filter:** `{exact predicate}`
- **Common mistake:** {which filter is forgotten and what it does to the number}
- **Parameters:** read from `{schema}.{table}`.`{column}` — never hardcoded
- **Fallback:** {behaviour when a parameter is absent for the period}
- **Deduplication:** unique per {grain}; resolve duplicates by {rule}

#### Type

<!-- Required — OKR or Health Metric. -->

{OKR | Health Metric}

#### Direction

<!-- Required — the metric's polarity. Exactly one of: Higher is better /
     Lower is better / Neutral. -->

{Higher is better | Lower is better | Neutral}

#### Grain

<!-- Required — the period one row of the metric covers. Default to monthly unless the
     metric is genuinely tracked at another frequency; the Golden Query below must
     aggregate at this same grain. One of: daily / weekly / monthly / quarterly /
     yearly. -->

monthly

#### Is Additive

<!-- Required — true when the metric can be summed across dimensions (counts, volumes),
     false when it cannot (rates, ratios, averages, percentages). Getting this wrong is
     how someone sums percentages and reports 340%. -->

{true | false}

#### MBR

<!-- Optional — the Monthly Business Review(s) this metric feeds. Omit when none. -->

{MBR Name}

#### Category

<!-- Optional — the MBR agenda block this metric occupies (e.g. Cost of Service). Only
     meaningful alongside an MBR; omit when unknown. -->

{MBR agenda block}

#### Golden Query

<!-- Required — one canonical query that PRODUCES this metric at the grain declared
     above. One sentence on what it returns, then the SQL. Must run on Trino AND on EMR
     Spark 3.5 (see the dialect rules in the writing guide at the top). -->

{One sentence on what this query computes.}

```sql
SELECT
    date_trunc('month', {date_column}) AS month,
    {metric_expression} AS {metric_alias}
FROM {schema}.{table}
WHERE {canonical_filter}
GROUP BY 1
ORDER BY 1
```

### {Metric Name B}

#### Slug

{metric_name_b}

#### Description

**{Metric Name B}** is {one-sentence definition}.

#### Also Known As

- **{term}**, **{synonym}**

#### Rules

- **Canonical filter:** `{exact predicate}`
- **Common mistake:** {which filter is forgotten and what it does to the number}

#### Type

{OKR | Health Metric}

#### Direction

{Higher is better | Lower is better | Neutral}

#### Grain

monthly

#### Is Additive

{true | false}

#### Golden Query

{One sentence on what this query computes.}

```sql
{second_metric_query}
```
