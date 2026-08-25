# Terminations With Repairs

## Ownership

**Data Owner:**
- carolina.espinoza@quintoandar.com.br

**Data Steward:**
- victor.prado@quintoandar.com.br

## Overview

**Terminations With Repairs** is the count of finished, non-eviction For Rent terminations for which at least one tenant repair was flagged during the exit inspection process (`has_repairs = true` on the pre-joined offboarding table). It is the raw incidence count behind the official **% Without Repairs** ratio documented in the Property Integrity Offboarding metric family — this document reports the numerator as an absolute count rather than a share, for use cases that need volume (e.g. operational staffing, repair-analysis queue sizing) rather than a rate.

**Exists exclusively for For Rent offboarding.**

## Related Domain Entities

- Termination

## Catalog

| Metric | Type |
| :---- | :---- |
| Terminations With Repairs | Health Metric |

## MBR

**Name** Post Contract
**Category** Resolution Effectiveness

## Glossary and Synonyms

- **Terminations With Repairs**, **reparos apontados**, **quantidade de terminations com reparo**, **contagem de reparos**, **terminations com pelo menos 1 reparo** → this metric
- **% Without Repairs** → near-miss — the official ratio metric this count is the complement/numerator of (see Property Integrity Offboarding), not this raw count
- **vistoria de saída**, **exit inspection** → near-miss — the inspection process that produces the `has_repairs` flag, not this metric itself

## Scope

**Included**: For Rent offboarding terminations that have already finished (`ts_termination_finished IS NOT NULL`), excluding evictions, where a tenant repair was flagged (`has_repairs = true`).

**Excluded**: evictions (`is_eviction = true`), canceled terminations (already removed upstream by the OBT), and terminations that have not yet reached closure (NULL `ts_termination_finished`). For Sale and any other product line — this metric has no equivalent outside For Rent offboarding.

## Calculation

The correct calculation is:

```
Terminations With Repairs = COUNT_IF(has_repairs = true)
```

evaluated over the finished, non-eviction base described in Scope. This is the same base and flag used by **% Without Repairs** (`count_if(has_repairs = false) / count(*)`) in the Property Integrity Offboarding metric family — this document reports `count_if(has_repairs = true)` directly as a volume, not divided by the base total.

A naive count over the full `obt_offboarding` table (without the canonical filter) overstates the number by including evictions and still-open terminations, which behave very differently on repairs.

### Canonical Filter

Apply on `dw_offboarding.obt_offboarding`:

```sql
is_eviction = false
AND ts_termination_finished IS NOT NULL
AND has_repairs = true
```

**Warning**: dropping `is_eviction = false` lets evictions into the count, and dropping `ts_termination_finished IS NOT NULL` includes terminations still in progress — both inflate the number with terminations that do not belong to the finished-quality population this metric measures.

### Nuances

No external weight or parameter table — `has_repairs` is a pre-materialized boolean flag on `obt_offboarding`, one row per termination (most recent exit inspection, canceled terminations already excluded upstream). No dedup logic is required beyond reading the table as-is.

**Join key**: not applicable — no parameter table to join.

**Fallback**: not applicable — the flag is populated whenever the termination reaches the finished state used by the canonical filter.

## Dos and Don'ts

**Do:**

- Always apply the full canonical filter (`is_eviction = false` AND `ts_termination_finished IS NOT NULL`) before counting.
- Use the exact `= true` boolean comparison on `has_repairs` — a NULL flag is neither `true` nor `false` and should not be coerced.
- Use the calendar date of `ts_termination_finished` (`CAST(ts_termination_finished AS DATE)`, UTC) as the reference axis for any period breakdown, to match operational monthly reporting.

**Don't:**

- Don't report this count as a rate — it is a raw volume; use **% Without Repairs** (or its complement) from the Property Integrity Offboarding metric family for a share.
- Don't `COALESCE(has_repairs, false)` before comparing — it changes nothing since NULL is already not `true`, and only obscures intent.
- Don't include evictions or still-open terminations in the count.

## Golden Queries

Monthly count of terminations with at least one repair flagged, last 12 closed months.

```sql
SELECT
    DATE_TRUNC('month', CAST(ts_termination_finished AS DATE)) AS ref_month,
    COUNT_IF(has_repairs = true) AS terminations_with_repairs
FROM dw_offboarding.obt_offboarding
WHERE is_eviction = false
  AND ts_termination_finished IS NOT NULL
  AND CAST(ts_termination_finished AS DATE) >= DATE_ADD('month', -12, CURRENT_DATE)
GROUP BY 1
ORDER BY 1
```
