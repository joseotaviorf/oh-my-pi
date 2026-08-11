# Eval Fixture Domain

## Ownership

**Data Owner:**
- eval.owner@quintoandar.com.br

**Data Steward:**
- eval.steward@quintoandar.com.br

## Overview

**Eval Fixture Domain** provides revised synthetic calendar guidance for
deployment tests while preserving the linked metric calculation. It is
not a production business domain. Overview edits here must fan out to
**Eval Fixture Metric** and keep dataset drift clean.

## Glossary and Synonyms

- **fixture date** → a calendar date used by the synthetic metric
- **Eval Fixture Domain** → synthetic routing domain for CI validation

## Tables

| Table | Purpose |
| --- | --- |
| `dw_public.dim_date` | Calendar dates used by the fixture query |

## Related Metric Entities

- Eval Fixture Metric

## Dos and Don'ts

**Do:**
- Use this entity only in isolated tests.
- Route Daily Fixture Count questions to Eval Fixture Metric.

**Don't:**
- Don't treat fixture semantics as production business rules.
- Don't invent listing/rent/sale SQL from this domain.

## Golden Queries

### Query 1 — Fixture Dates

```sql
SELECT date
FROM dw_public.dim_date
WHERE date >= DATE '2026-01-01'
ORDER BY 1
```
