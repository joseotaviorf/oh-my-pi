# Inspection SLA (SLA - VT)

## Ownership

**Data Owner:**
- [joao.mariani@quintoandar.com.br](mailto:joao.mariani@quintoandar.com.br)

**Data Steward:**
- [victor.sakai@quintoandar.com.br](mailto:victor.sakai@quintoandar.com.br)

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

## Related Business Entities

- Inspection

## MBR

- Post Contract

## Glossary and Synonyms

- **SLA - VT**, **SLA de Vistoria**, **Inspection SLA**, **Produtividade de Vistoria** → Inspection SLA
- **target de sla de vistoria**, **meta de SLA**, **target de sla de onb+off** → Inspection SLA

## Scope

**Included**:
- Executed inspections (`fi_dt_inspected IS NOT NULL`) within the last 13 months.
- Inspections categorized as `onboarding` or `offboarding` (`di_inspection_type`).
- Only valid, non-duplicated records (`removing_duplicate = 1` and `RANK_SLA = 1`).
- Active or non-canceled contracts (where `status_contract` is not `'CANCELED'` or is NULL).
- Eviction cases ("Despejo") are included in the base but can be filtered out or
  analyzed separately using the `category` field.

**Excluded**:
- Canceled inspections or verification inspections (`verification`).
- Unfinished/unexecuted inspections (`fi_dt_inspected IS NULL`).
- Canceled contracts (`status_contract = 'CANCELED'`).
- Duplicated inspection bookings.

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

**Don't:**
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

Calculates the monthly Inspection SLA for Onboarding and Offboarding. The results are
grouped by `di_inspection_type` and `category` to allow analyzing standard journeys
versus Evictions (Despejos).

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
