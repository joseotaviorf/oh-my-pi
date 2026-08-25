# Eval Fixture Metric

## Ownership

**Data Owner:**
- eval.owner@quintoandar.com.br

**Data Steward:**
- eval.steward@quintoandar.com.br

## Overview

**Eval Fixture Metric** is a synthetic metric used only to verify the
`docs/llm_context` evaluation deployment pipeline (including durable
Inspect archive to S3). It is not a production KPI and must not be used
for business reporting.

When the user asks for **Daily Fixture Count**, answer with the SQL from
this document's Golden Queries section only. Do not use listing, rent,
sale, contract, or customer-contact tables. The only allowed source table
is `dw_public.dim_date`.

## Related Domain Entities

- Eval Fixture Domain

## Glossary and Synonyms

- **Daily Fixture Count**, **fixture count**, **eval fixture metric** →
  count of calendar dates in `dw_public.dim_date` on or after
  `DATE '2026-01-01'`

## Scope

**Included:** calendar dates on or after `DATE '2026-01-01'` from
`dw_public.dim_date`.

**Excluded:** any production metric table; listing/rent/sale facts;
non-fixture calendar sources.

## Calculation

```
Daily Fixture Count(date) = COUNT(*) FROM dw_public.dim_date
WHERE date >= DATE '2026-01-01'
GROUP BY date
```

### Canonical Filter

```sql
date >= DATE '2026-01-01'
```

## Dos and Don'ts

**Do:**
- Use only `dw_public.dim_date`.
- Return one row per `date` with `fixture_count`.
- Prefer the Golden Query in this document verbatim.

**Don't:**
- Don't use listing, rent, sale, or customer-contact tables.
- Don't replace the fixture table with a production metric table.
- Don't invent country or last-30-day filters.

## Golden Queries

### Query 1 — Daily Fixture Count

```sql
SELECT
    date AS metric_date,
    COUNT(*) AS fixture_count
FROM dw_public.dim_date
WHERE date >= DATE '2026-01-01'
GROUP BY 1
ORDER BY 1
```
