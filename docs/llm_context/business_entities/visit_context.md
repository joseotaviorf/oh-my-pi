# Visit

> **DataHub Data Product:** `urn:li:dataProduct:visits` (Domain: Growth) **Trino validation:** ✅ All 6 tables and 4 golden queries validated against Trino (2026-06-19).

* * *

## Overview

A **visit** is the full lifecycle event that tracks a potential tenant or buyer from initial booking (schedule) through to the actual property viewing. The Visit entity groups all rescheduling attempts under a single `sk_visit`, giving a true conversion view per customer/property.

The domain covers two distinct analytical lenses:

1.  **Visit View** — answers funnel questions (conversion rate from scheduled to completed visit, broker efficiency, property attractiveness). Use `dw_visit.fact_visits` + `dw_visit.dim_visit`.
    
2.  **Schedule View** — answers operational questions (how many times was a booking cancelled or rescheduled before the visit happened). Use `dw_visit.fact_visit_schedules` + `dw_visit.dim_visit_schedule`.
    

A visit is the strongest signal of transaction intent and feeds downstream offer and contract conversion metrics. It applies to both the **For Rent** and **For Sale** business contexts via `dim_visit.business_context`.

* * *

## Glossary and Synonyms

*   **Visita / Visit** (`sk_visit`) → the canonical visit entity, grouping one or more schedules. One row per visit.
    
*   **Schedule / Agendamento** (`sk_schedule`) → a single booking attempt within a visit. A visit may have N schedules (reschedules). Never count `sk_schedule` as unique visits.
    
*   **VB2VC** (Visit Booked to Visit Completed) → primary funnel conversion rate: `SUM(num_visit_completed) / SUM(num_visit_booked)`.
    
*   **Visit Completed** (`is_visit_completed = TRUE`, `computed_status = 'DONE'`) → broker marked visit as done.
    
*   **Visit Unsuccessful** (`is_visit_unsuccessful = TRUE`, `computed_status = 'UNSUCCESSFUL'`) → visit attempt failed (e.g. demand no-show, access issue).
    
*   **Visit Cancelled** (`is_visit_canceled = TRUE`) → visit was cancelled before happening; use `cancellation_reason` to distinguish demand-led, supply-led, or broker-led.
    
*   **Post-visit demand evaluation** (`dim_post_visit_demand`) → qualitative feedback from the demand side after a completed or contested visit.
    
*   **Entrance model / Acesso** (`dim_house_entrance_history`) → how the property is accessed: `FRONT_DOOR`, `OWNER`, `PASSWORD`, `LOCK_BOX`, etc. Stored in `key_location`.
    
*   **Business context** → `'FOR_RENT'` or `'FOR_SALE'`. Always segment or filter by `dv.business_context` before aggregating.
    

* * *

## Tables

| You need… | Use this table |
| --- | --- |
| Funnel conversion metrics (VB2VC, offer, contract) | `dw_visit.fact_visits` — one row per visit; pre-aggregated `num_*` measures and full SK dimension set |
| Visit attributes (status, cancellation reason, source, business context, timestamps) | `dw_visit.dim_visit` — enriches `fact_visits` on `sk_visit`; use `ts_visit` as the partition/time column |
| History of individual booking attempts (reschedules, operational analysis) | `dw_visit.fact_visit_schedules` — one row per schedule attempt; join to `dim_visit_schedule` on `sk_schedule` |
| Schedule-level attributes (channel, confirmation flags, `is_last_schedule`) | `dw_visit.dim_visit_schedule` — use `is_last_schedule = TRUE` to isolate the final/valid attempt |
| Post-visit qualitative feedback from demand | `dw_visit.dim_post_visit_demand` — one row per visit; join on `sk_visit`; includes `channel`, ratings, and `is_visit_completed_by_demand` |
| Property access/entrance model data | `dw_house.dim_house_entrance_history` — join `fact_visits.sk_house_entrance = dim_house_entrance_history.sk_house_entrance`; use `is_last_status = TRUE` for the current model |

**Critical rules:**

*   Always include a **partition guard** on `dw_visit.dim_visit.ts_visit` (e.g., `ts_visit >= CURRENT_DATE - INTERVAL '6' MONTH`) to avoid full scans.
    
*   **Never count** `sk_schedule` as unique visits. A single visit can produce 3+ schedules via reschedule.
    
*   Filter `dim_visit_schedule.is_last_schedule = TRUE` when you want only the final booking attempt per visit.
    
*   Use `dim_visit.computed_status` to distinguish `'DONE'` (completed) from `'UNSUCCESSFUL'` (attempted but failed) — do not rely on `status` alone.
    
*   `dim_visit.business_context` applies to both rent and sale — always filter or segment by it before cross-context aggregation.
    
*   Do not mix `dim_house_entrance_history` with visit status without verifying the entrance model was active at the time of the visit (`ts_entrance_started` / `ts_entrance_ended`).
    

* * *

## Key Metrics

All measures below come from `dw_visit.fact_visits` (prefix `fv`) unless noted.

*   **Visits booked** — `SUM(fv.num_visit_booked)`
    
*   **Visits completed** — `SUM(fv.num_visit_completed)`
    
*   **VB2VC rate** — `SUM(CAST(fv.num_visit_completed AS DOUBLE)) / SUM(CAST(fv.num_visit_booked AS DOUBLE))`
    
*   **Visits cancelled** — `SUM(fv.num_visit_canceled)`
    
*   **Visits unsuccessful** — `SUM(fv.num_visit_unsuccessful)`
    
*   **Offers submitted** — `SUM(fv.num_offer_submitted)` (visit → offer funnel)
    
*   **Contracts signed** — `SUM(fv.num_contract_signed)` (visit → contract funnel)
    
*   **Post-visit demand evaluations** — `SUM(fv.num_post_visit_demand)`
    
*   **Visits completed confirmed by demand** — `SUM(fv.num_visit_completed_by_demand)`
    
*   **Visits contested by demand** (`vc_contested_rate`) — `SUM(fv.num_visit_unsuccessful_by_demand) / SUM(fv.num_visit_completed)`
    
*   **Number of reschedules** — `fv.nbr_reschedule` (per visit)
    
*   **Journey days** (first booking to completion) — `fv.journey_days`
    

* * *

## Relationships with Other Entities

### dim_visit (N:1 per visit)

```sql
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit

```

Use to enrich with: `business_context`, `computed_status`, `cancellation_reason`, `visit_request_source_unified`, `ts_visit` (partition key), and all boolean flags.

### fact_visit_schedules → dim_visit_schedule (1:N per visit)

```sql
JOIN dw_visit.dim_visit_schedule AS dvs
  ON fvs.sk_schedule = dvs.sk_schedule
WHERE dvs.is_last_schedule = TRUE  -- final attempt only

```

`fact_visit_schedules` has one row per schedule attempt. `dim_visit_schedule` adds channel, confirmation flags, and `is_last_schedule`.

### dim_post_visit_demand (1:1 per visit, nullable)

```sql
LEFT JOIN dw_visit.dim_post_visit_demand AS pvd
  ON fv.sk_post_visit_demand = pvd.sk_visit

```

Not all visits have a post-visit evaluation. Always use `LEFT JOIN`. Provides `channel` (conventional vs IA), `agent_rating`, `house_rating`, and `is_visit_completed_by_demand`.

### dim_house_entrance_history (N:1 per visit)

```sql
JOIN dw_house.dim_house_entrance_history AS dim_h
  ON fv.sk_house_entrance = dim_h.sk_house_entrance

```

Exposes `key_location` (entrance model). For current model only, add `WHERE dim_h.is_last_status = TRUE`.

* * *

## Dos and Don'ts

**Do:**

*   Use `dw_visit.fact_visits` for all funnel conversion metrics (VB2VC, offer, contract).
    
*   Always filter or segment by `dv.business_context` (`'FOR_RENT'` / `'FOR_SALE'`) before aggregating.
    
*   Include `ts_visit >= CURRENT_DATE - INTERVAL 'N' MONTH` in every query touching `dim_visit` for partition pruning.
    
*   Use `is_last_schedule = TRUE` in `dim_visit_schedule` when you want one row per visit from the schedules table.
    
*   Join `dim_post_visit_demand` to understand why a completed visit did not generate a proposal (qualitative signal).
    
*   Use `dv.computed_status` to distinguish `'DONE'` vs `'UNSUCCESSFUL'` — do not assume `visit_status = 'completed'` is enough.
    
*   Cast numerics explicitly when computing rates: `SUM(CAST(num_visit_completed AS DOUBLE)) / SUM(CAST(num_visit_booked AS DOUBLE))`.
    
*   Enrich schedule-level analysis from `fact_visit_schedules` with `dim_visit` for fields that don't change between schedules (e.g. `visit_code`, `business_context`).
    

**Don't:**

*   Don't count `sk_schedule` as unique visits — a rescheduled visit generates N schedules but only 1 `sk_visit`.
    
*   Don't assume `cancellation_reason = 'demand'` without checking `cancellation_on_behalf_of` — cancellations can be broker-led, supply-led, or system-expired.
    
*   Don't mix entrance model data (`dim_house_entrance_history`) with visit outcomes without validating the model was active at visit time.
    
*   Don't use `dw_visits.*` — the schema is `dw_visit` (no trailing 's'). The DataHub golden query contains a typo on this.
    
*   Don't skip `business_context` filtering when comparing For Rent and For Sale — metrics have different baselines.
    

* * *

## Golden Queries

> ✅ All queries validated against Trino (2026-06-19). Results confirmed: Q1 returns 7 months of data, Q2 splits RENT/SALE correctly, Q3 returns 10 entrance models, Q4 returns demand channel breakdown.

### Query 1 — VB2VC rate by month

Monthly visit booked to visit completed conversion rate.

```sql
SELECT
    DATE_TRUNC('month', dv.ts_visit) AS month_ref,
    SUM(fv.num_visit_booked)         AS total_visits_booked,
    SUM(fv.num_visit_completed)      AS completed_visits,
    SUM(CAST(fv.num_visit_completed AS DOUBLE))
        / SUM(CAST(fv.num_visit_booked AS DOUBLE)) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '6' MONTH
GROUP BY 1
ORDER BY 1 DESC;

```

Segment by `dv.business_context` to split For Rent vs For Sale.

### Query 2 — VB2VC by business context

```sql
SELECT
    dv.business_context,
    SUM(fv.num_visit_booked)    AS total_visits_booked,
    SUM(fv.num_visit_completed) AS completed_visits,
    SUM(CAST(fv.num_visit_completed AS DOUBLE))
        / SUM(CAST(fv.num_visit_booked AS DOUBLE)) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '6' MONTH
GROUP BY 1
ORDER BY 1 DESC;

```

### Query 3 — VB2VC by entrance model (access performance)

Identifies which property access methods lead to higher completion rates.

```sql
SELECT
    dim_h.key_location,
    SUM(fv.num_visit_booked)    AS vb,
    SUM(fv.num_visit_completed) AS vc,
    SUM(CAST(fv.num_visit_completed AS DOUBLE))
        / SUM(CAST(fv.num_visit_booked AS DOUBLE)) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
JOIN dw_house.dim_house_entrance_history AS dim_h
  ON fv.sk_house_entrance = dim_h.sk_house_entrance
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY 1
ORDER BY vb DESC;

```

### Query 4 — Visit contested rate by demand channel

Identifies completed visits later contested by demand, segmented by channel (conventional vs IA).

```sql
SELECT
    pvd.channel,
    SUM(fv.num_visit_completed)              AS vc_by_agent,
    SUM(fv.num_visit_unsuccessful_by_demand) AS vu_by_demand,
    SUM(CAST(fv.num_visit_unsuccessful_by_demand AS DOUBLE))
        / SUM(CAST(fv.num_visit_completed AS DOUBLE)) AS vc_contested_rate
FROM dw_visit.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
JOIN dw_visit.dim_post_visit_demand AS pvd
  ON fv.sk_post_visit_demand = pvd.sk_visit
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '60' DAY
  AND dv.is_visit_completed
GROUP BY 1;

```

* * *

## DataHub catalog

- **Data Product:** `urn:li:dataProduct:visit-context`

