# Visit Funnel 

## Ownership

**Data Owner:**
- leticia.machado@quintoandar.com.br

**Data Steward:**
- leticia.machado@quintoandar.com.br

## Overview

**Visit Funnel ** materializes visit-grain funnel counts (booked and completed visits)
sliced by business context (RENT/SALE) and visit status. It is the QUBE-backed counterpart to
the component VB/VC metrics documented in the Visits business entity, using **entity presence**
on `core_visit.visit` rather than daily pre-aggregates on `dw_visit.fact_visits`.

**Applies to both for rent and for sale** (`business_context` on the visit entity).

## Related Domain Entities

- Visits

## Catalog

| Metric | Type |
| :---- | :---- |
| Visit Funnel  | Health Metric |

## DataHub Catalog

- **This metric's data product**: `urn:li:dataProduct:visit-funnel-`
- **Upstream business entity data product**: `urn:li:dataProduct:visits`
- **QUBE materialization** (exploration):
  - Dimensions: `qube_dimensions.visit__business_context__*`, `qube_dimensions.visit__visit_status__*`
  - Measures: `qube_measures.visit__visit_booked__*`, `qube_measures.visit__visit_completed__*`
  - Metric: `qube_metrics.visit__visit_funnel___*`

## Glossary and Synonyms

- **Visit funnel **, **VB VC **, **visit booked completed counts** → this metric
- **VB**, **VC** — component visit booked / visit completed (see Visits business entity)

## Scope

**Included**: All visits in `core_visit.visit` with a valid `id_visit`, both RENT and SALE
`business_context` values.

**Excluded**: Schedule-grain rows (`fact_visit_schedules`); listing-cohort L2VB/L2VC (see
[Listing Demand Funnel Conversions](listing_demand_funnel_conversions.md)).

## Calculation

QUBE counts **distinct visit entities** (`id_visit`) in rolling windows (1d, 7d, 28d):

```
visit_booked     = visits where ts_visit_requested IS NOT NULL (event date in window)
visit_completed  = visits where ts_visit_done IS NOT NULL (event date in window)
```

The  metric joins the `business_context` and `visit_status` dimensions with both
measures and emits exact (`long`) counters. Exploration phase uses `k_anonymity: 1` (no
suppression).

### Canonical Filter

Source entity table: `core_visit.visit` (default QUBE resolution).

No additional business filter beyond the measure predicates above. For Trino reconciliation
against `dw_visit.fact_visits`, apply a date filter on visit time:

```sql
CAST(ts_visit_local_tz AS DATE) >= CURRENT_DATE - INTERVAL '6' MONTH
```

### Nuances

- **Grain**: one row per **visit** (`id_visit`), not per schedule attempt.
- **Booked**: aligned with `VISIT_REQUESTED` lifecycle (`ts_visit_requested` on core visit).
- **Completed**: aligned with `VISIT_DONE` lifecycle (`ts_visit_done` on core visit).
- **Reconciliation**: `SUM(num_visit_booked)` on `fact_visits` is daily pre-aggregated; QUBE
  measures count distinct entities — compare trends, not necessarily point totals.

## Dos and Don'ts

**Do:**

- Use this metric entity for QUBE/TARS discovery of visit-grain VB/VC  counts.
- Read schema and component definitions from the [Visits](../business_entities/visits.md)
  business entity.
- Filter by `business_context` when comparing RENT vs SALE.

**Don't:**

- Don't use `fact_visit_schedules` for visit-entity funnel counts.
- Don't mix listing-cohort L2VB/L2VC with this visit-grain metric.
- Don't assume exact equality with `SUM(num_visit_*)` on `fact_visits` without reconciliation.

## Golden Queries

Component pattern (Trino) — same as Visits business entity VB2VC component:

```sql
SELECT
    DATE_TRUNC('month', CAST(ts_visit_local_tz AS DATE)) AS month_ref,
    SUM(num_visit_booked) AS total_visits_booked,
    SUM(num_visit_completed) AS completed_visits,
    CAST(SUM(num_visit_completed) AS DOUBLE) / NULLIF(SUM(num_visit_booked), 0) AS vb2vc_rate
FROM dw_visit.fact_visits
WHERE CAST(ts_visit_local_tz AS DATE) >= CURRENT_DATE - INTERVAL '6' MONTH
GROUP BY 1
ORDER BY 1 DESC;
```

QUBE exploration (after Forno run) — example 7d window:

```sql
SELECT
    business_context,
    visit_status,
    visit_booked,
    visit_completed
FROM qube_metrics.visit__visit_funnel___7d
WHERE dt_reference = CURRENT_DATE - INTERVAL '1' DAY
ORDER BY 1, 2;
```
