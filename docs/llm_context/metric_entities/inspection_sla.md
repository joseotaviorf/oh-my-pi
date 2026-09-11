# Inspection SLA (SLA - VT)

## Ownership

**Data Owner:**
- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)

**Data Steward:**
- [victor.sakai@quintoandar.com.br](mailto:victor.sakai@quintoandar.com.br)
- [pedro.feres@quintoandar.com.br](mailto:pedro.feres@quintoandar.com.br)

## Overview

**Inspection SLA (SLA - VT)** measures the percentage of property inspections completed
within the expected and established timeframe. It evaluates the operational
productivity by checking if the inspections were delivered on time according to the
lease lifecycle stage.

**This metric applies to Onboarding and Offboarding inspections only.**
- **Onboarding**: the inspection must be executed up to 2 calendar days before the
  contract start date (`fi_dt_contract_entrance`).
- **Offboarding**: the inspection must be executed up to 3 business days after the
  tenant's departure date (`ww_dt_end_3`).

> ⚠️ **Official metric excludes Eviction ("Despejo")**: The metric as reported in the
> EMB-R (see [MBR](#mbr) and [Targets and OKRs](#targets-and-okrs) below) is **SLA VT
> Onb + Off s/ Despejo** — i.e. it is always calculated **without** eviction cases.
> Whenever the *official* Inspection SLA is being calculated (not an ad-hoc breakdown
> requested by the user), eviction cases must be removed by filtering
> `category <> 'EVICTION'` (or the NULL-safe equivalent) out of both the numerator and
> the denominator. Only keep eviction cases in when the user explicitly asks to analyze
> or compare Despejo separately.

## Related Domain Entities

- Inspection

## Catalog

| Metric | Type |
| :---- | :---- |
| Inspection SLA (SLA - VT) | Health Metric |

## MBR

**Name** Post Contract
**Category** CS Quality

## Glossary and Synonyms

- **SLA - VT**, **SLA de Vistoria**, **Inspection SLA**, **Produtividade de Vistoria**, **SLA de inspections**→ Inspection SLA
- **target de sla de vistoria**, **meta de SLA**, **target de sla de onb+off** → Inspection SLA

## Scope

**Included**:
- Executed inspections (`fi_dt_inspected IS NOT NULL`) within the last 13 months.
- Inspections categorized as `onboarding` or `offboarding` (`di_inspection_type`).
- Only valid, non-duplicated records (`removing_duplicate = 1` and `RANK_SLA = 1`).
- Active or non-canceled contracts (where `status_contract` is not `'CANCELED'` or is NULL).
- Eviction cases ("Despejo") exist in the base table and remain available for ad-hoc
  slicing/comparison via the `category` field, but see **Excluded** below — for the
  **official** metric they must be removed.

**Excluded**:
- Canceled inspections or verification inspections (`verification`).
- Unfinished/unexecuted inspections (`fi_dt_inspected IS NULL`).
- Canceled contracts (`status_contract = 'CANCELED'`).
- Duplicated inspection bookings.
- **Eviction ("Despejo") cases (`category = 'EVICTION'`) — excluded by default from the
  official Inspection SLA**, since that's how it's tracked in the EMB-R
  (`SLA VT Onb + Off s/ Despejo`). Only include them when the user explicitly asks to
  look at Despejo specifically.

## Calculation

The metric is calculated as the ratio of inspections completed on time
(SLA - Numerador) divided by the total number of executed valid inspections
(SLA - Denominador).

The correct calculation is:

```
Inspection SLA = SLA - Numerador / SLA - Denominador
```

where:
- **SLA - Numerador**:
  - If `offboarding`: `date(fi_dt_inspected) <= ww_dt_end_3` AND `RANK_SLA = 1` AND
    `(status_contract NOT IN ('CANCELED') OR status_contract IS NULL)`
  - If `onboarding`: `date_diff('day', fi_dt_contract_entrance, date(fi_dt_inspected)) < 1`
    AND `RANK_SLA = 1` AND `(status_contract NOT IN ('CANCELED') OR status_contract IS NULL)`
- **SLA - Denominador**:
  - `fi_dt_inspected IS NOT NULL` AND `RANK_SLA = 1` AND
    `(status_contract NOT IN ('CANCELED') OR status_contract IS NULL)`

> **For the official metric**, add `category <> 'EVICTION'` to both the SLA - Numerador
> and SLA - Denominador conditions above, since the EMB-R view of this metric never
> includes Despejo.

### Canonical Filter

Apply on `sandbox.booking_resolution`:

```sql
di_inspection_type IN ('onboarding', 'offboarding')
AND removing_duplicate = 1
AND (
    fi_ts_synced >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '13' MONTH
    OR fi_ts_booking_inspected_local >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '13' MONTH
)
```

### Nuances

| Column | Description |
| :---- | :---- |
| `di_inspection_type` | Defines the lease stage: `onboarding` or `offboarding`. |
| `fi_dt_inspected` | Timestamp of when the inspection was actually executed. |
| `fi_dt_contract_entrance` | The start date of the rental contract (used for onboarding SLA). |
| `ww_dt_end_3` | The 3rd business day after the tenant's departure (used for offboarding SLA). |
| `removing_duplicate` | Flag used to ensure bookings are not counted multiple times (must equal 1). |
| `RANK_SLA` | Ranks inspections to pick the appropriate one for the SLA denominator/numerator (must equal 1). |
| `category` | Categorizes the contract/termination context. Use `category = 'EVICTION'` to isolate "Despejo" cases. |

## Dos and Don'ts

**Do:**
- Always use the materialized table `sandbox.booking_resolution` to query this metric.
- Apply the 13-month rolling window filter using `fi_ts_synced` or `fi_ts_booking_inspected_local`.
- Always filter out duplicated lines by strictly applying `removing_duplicate = 1`.
- Ensure `RANK_SLA = 1` and the contract status check
  (`status_contract NOT IN ('CANCELED') OR status_contract IS NULL`) are applied when
  summing the Numerator and Denominator.
- Use the `category` column to slice standard offboarding vs. eviction (Despejo) cases
  when requested.
- **Always exclude eviction cases (`category = 'EVICTION'`) when calculating the
  official Inspection SLA** — this matches how the metric is reported in the EMB-R
  (`SLA VT Onb + Off s/ Despejo`). Only keep Despejo in the base when the user
  explicitly asks to see it included or broken out.

**Don't:**
- Don't report a "SLA - VT" / "Inspection SLA" number as the official metric without
  filtering out eviction (Despejo) cases first, unless explicitly asked to include them.
- Don't try to calculate business days manually in the query; always rely on the
  `ww_dt_end_3` column.
- Don't include `verification` or other `di_inspection_type` values in the general SLA
  calculation.
- Don't forget to rule out canceled contracts (`status_contract = 'CANCELED'`), as they
  skew the base.

## Targets and OKRs

**OKR** — period operational goal for Inspection SLA, stored in a centralized KPI
targets table alongside other service metrics.

- **Source table:** `datalake_gsheets_clean.target_service_kpis`
- **Filter key / metric name:** `SLA VT Onb + Off s/ Despejo`
- **Period grain:** monthly (filter by the reference period column in the source table)
- **Aliases / search terms:** meta de SLA, target de sla de vistoria, target de sla de onb+off
- **Caveat:** This official OKR **does not include eviction cases ("Despejo")**. When
  comparing actual calculated SLA against this OKR, filter out eviction cases from
  actuals (e.g., excluding `category = 'EVICTION'`).

## Golden Queries

Calculates the monthly **official** Inspection SLA for Onboarding and Offboarding,
matching the EMB-R (`SLA VT Onb + Off s/ Despejo`). Eviction ("Despejo") cases are
removed via `(category IS NULL OR category <> 'EVICTION')` in the `base_inspections`
WHERE clause — the `IS NULL` branch is required because `category` is only populated
for offboarding rows with a matching termination record (onboarding rows have
`category IS NULL` and must **not** be dropped by the filter). The results are still
grouped by `di_inspection_type` and `category` so remaining (non-eviction) categories
can be inspected individually.

> If the user explicitly asks to analyze or include eviction/Despejo cases, remove the
> `(category IS NULL OR category <> 'EVICTION')` filter from the `WHERE` clause below
> instead of adjusting the aggregation.

```sql
WITH base_inspections AS (
    SELECT
        DATE_TRUNC('month', DATE(fi_dt_inspected)) AS ref_month,
        di_inspection_type,
        category,
        CASE
            WHEN (DATE(fi_dt_inspected) <= DATE(ww_dt_end_3) AND di_inspection_type = 'offboarding') AND RANK_SLA = 1 AND (status_contract NOT IN ('CANCELED') OR status_contract IS NULL) THEN 1
            WHEN (DATE_DIFF('day', DATE(fi_dt_contract_entrance), DATE(fi_dt_inspected)) < 1 AND di_inspection_type = 'onboarding') AND RANK_SLA = 1 AND (status_contract NOT IN ('CANCELED') OR status_contract IS NULL) THEN 1
            ELSE 0
        END AS sla_numerador,
        CASE
            WHEN fi_dt_inspected IS NOT NULL AND RANK_SLA = 1 AND (status_contract NOT IN ('CANCELED') OR status_contract IS NULL) THEN 1
            ELSE 0
        END AS sla_denominador
    FROM sandbox.booking_resolution
    WHERE di_inspection_type IN ('onboarding', 'offboarding')
      AND removing_duplicate = 1
      AND (category IS NULL OR category <> 'EVICTION') -- official metric: exclude Despejo (see Overview/Scope)
      AND (
          fi_ts_synced >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '13' MONTH
          OR fi_ts_booking_inspected_local >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '13' MONTH
      )
)
SELECT
    ref_month,
    di_inspection_type,
    category,
    SUM(sla_numerador) AS sla_numerador,
    SUM(sla_denominador) AS sla_denominador,
    CAST(SUM(sla_numerador) AS DOUBLE) / NULLIF(CAST(SUM(sla_denominador) AS DOUBLE), 0) AS inspection_sla
FROM base_inspections
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3
```

## Superset Golden Assets

- **Booking Resolution Sandbox** — Materialized in `sandbox.booking_resolution`.

