# Orphan Fixture Domain

## Ownership

**Data Owner:**
- eval.owner@quintoandar.com.br

**Data Steward:**
- eval.steward@quintoandar.com.br

## Overview

**Orphan Fixture Domain** intentionally has no metric doc pointing at it, so
the scope resolver must resolve it to zero stems and stay quiet.

## Glossary and Synonyms

- **orphan fixture** → a domain entity with no linked metric

## Tables

| Table | Purpose |
| --- | --- |
| `dw_public.dim_date` | Calendar dates unused by any fixture metric |

## Dos and Don'ts

**Do:**
- Keep this entity isolated from metric fixtures.

**Don't:**
- Don't invent metric links for this orphan fixture.

## Golden Queries

### Query 1 — Orphan Dates

```sql
SELECT date
FROM dw_public.dim_date
WHERE date >= DATE '2026-01-01'
ORDER BY 1
```
