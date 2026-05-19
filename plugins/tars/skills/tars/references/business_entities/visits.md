# Visits

## Overview

This document covers **visit analytics**, tracking the journey from the initial booking (schedule) to the actual event at the property. This domain consolidates interactions between potential tenants/buyers (demand), brokers, and landlords (supply).

**Scope:** The entire lifecycle of a visit, including scheduling, property entrance models, post-visit feedback, and funnel conversion.

Why this scope matters: A visit is the strongest signal of transaction intent. Unlike an isolated schedule, the **Visit Entity** groups multiple rescheduling events to provide a true view of conversion per customer/property.

Before answering any visit question, decide which lens applies:

| View | What it answers | When to use |
|------|-----------------|-------------|
| **Visit View** | What is the conversion rate from completed visits to proposals? | Funnel analysis, broker efficiency, and property attractiveness. |
| **Schedule View** | How many times was a booking canceled or rescheduled before the visit happened? | Operational analysis of scheduling churn and platform usage behavior. |

## Synonyms

| Term | Meaning |
|------|---------|
| **Booking / Schedule** | An individual appointment for a specific date and time. |
| **Visit** | The consolidated business entity (can contain one or more schedules). |
| **House Entrance** | The method of access to the property (Frontdoor, Owner, Lockbox, Broker-held keys, etc.). |
| **VB2VC** | *Visit Booked to Visit Completed* (Efficiency metric of the scheduling process). |
| **VB** | Visit Booked. |
| **VC** | Visit Completed. |
| **VCc** | Visit Canceled. |
| **VCf** | Visit Confirmed. |
| **VU** | Visit Unsuccessful. |
| **OS** | Offer Sent. |
| **OA** | Offer Accepted. |
| **CS** | Contract Signed. |
| **CCV** | Compromisso de Compra e Venda. |
| **No-show** | When one of the parties (demand, broker or supply) fails to appear at the scheduled time. |
| **Unsuccessful Visit** | A visit where the parties arrived but could not enter the property (e.g., missing keys). |

## Tables

| You need… | Schema / table |
|-----------|----------------|
| Consolidated **visit** view (final status, funnel metrics) | `dw_visit.fact_visits` |
| History of each individual **schedule** (reschedules/attempts) | `dw_visit.fact_visit_schedules` |
| Detailed visit attributes (source, cancel reason, context) | `dw_visit.dim_visit` |
| Confirmation details and lifecycle timestamps per schedule | `dw_visit.dim_visit_schedule` |
| Post-visit evaluations (feedback from demand) | `dw_visit.dim_post_visit_demand` |
| Property entrance and key management data | `dw_house.dim_house_entrance_history` |

### The `dw_visit` building blocks

#### `fact_visits`

**visit** grain: one row per consolidated visit.

| Topic | Fields |
|-------|--------|
| Keys | `sk_visit`, `sk_visitor`, `sk_house`, `sk_house_entrance`, `sk_post_visit_demand`|
| Numerical Measurements | `num_visit_booked`, `num_visit_completed`, `num_visit_canceled`, `num_visit_unsuccessful`, `num_offer_submitted`, `num_visit_unsuccessful_by_demand`, `num_agents_associated`, `nbr_bookings` |
| Funnel | `sk_funnel_offer_submitted`, `sk_funnel_offer_accepted`, `sk_funnel_contract_signed` |

#### `fact_visit_schedules`

**schedule** grain: one row per schedule/booknig.

| Topic | Fields |
|-------|--------|
| Keys | `sk_schedule`, `sk_visit`, `sk_visit`, `sk_visitor`, `sk_house`, `sk_house_entrance` |
| Numerical Measurements | `days_visit_cancelled_to_visit`, `days_visit_booked_to_visit`, `days_visit_booked_to_cancelled`, `days_visit_booked_to_visit_completed` |

## Dos and Don'ts

**Do:**

- Use **`dw_visit.fact_visits`** for funnel conversion metrics (e.g., visits that turned into offers).
- Use numerical measurements from **`dw_visit.fact_visits`** to calculate the metric visits.
- Use the same tables for both for rent and for sale business contexts (**`dw_visit.dim_visit.business_context`**).
- Always filter by **`is_last_schedule = TRUE`** in the schedules table if you want to see only the final/valid attempt for a visit.
- Join **`dim_post_visit_demand`** to understand why a completed visit did not generate a proposal (qualitative feedback).
- Check the **`dw_visit.dim_visit.computed_status`** to distinguish between "DONE" visits and "UNSUCCESSFUL" visits (where a visit was attempted but failed).
- Include a partition guard (e.g., `ts_visit >= CURRENT_DATE - INTERVAL '6' MONTHS`) to optimize query performance.
- Use the **`dw_visit.dim_visit`** to enrich the schedule tables for fields that don't change between schedules (e.g., visit_code, business_context).

**Don't:**

- Don't count `sk_schedule` as unique visits; a user may reschedule the same visit 3 times, generating 4 schedules but only 1 `sk_visit`.
- Don't assume `visit_status = 'cancelled'` implies a system error; use `cancel_reason` to distinguish between demand-led, supply-led, or broker-led cancellations.
- Don't mix `house_entrance` data with visit status without validating if the entrance model was available at the time of the visit.
- Don't use the **`dw_visit.dim_visit`** to enrich the schedule tables when the fields from dim_visit can change between the schedules (e.g., each schedule can be confirmed while the confirmation field from dim_visit is about the last schedule).

## Golden queries

### 1. Visit Booked to Visit Completed (VB2VC) Rate

#### The primary metric for understanding scheduling efficiency and completion.

```sql
SELECT
    DATE_TRUNC('month', dv.ts_visit) AS month_ref,
    SUM(fv.num_visit_booked) AS total_visits_booked,
    SUM(fv.num_visit_completed) AS completed_visits,
    SUM(CAST(fv.num_visit_completed AS DOUBLE)) / SUM(CAST(fv.num_visit_booked AS DOUBLE)) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '6' MONTH
GROUP BY 1
ORDER BY 1 DESC;
```

#### The primary metric for understanding scheduling efficiency and completion by business context

```sql
SELECT
    dv.business_context,
    SUM(fv.num_visit_booked) AS total_visits_booked,
    SUM(fv.num_visit_completed) AS completed_visits,
    SUM(CAST(fv.num_visit_completed AS DOUBLE)) / SUM(CAST(fv.num_visit_booked AS DOUBLE)) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '6' MONTH
GROUP BY 1
ORDER BY 1 DESC;
```

### 2. Visits by Entrance Model (Access Performance)

Identifies which access methods (e.g., FRONT_DOOR, OWNER, PASSWORD, LOCK_BOX) lead to higher completion rates.

```sql
SELECT
    dim_h.key_location,
    SUM(fv.num_visit_booked) AS vb,
    SUM(fv.num_visit_completed) AS vc,
    SUM(CAST(fv.num_visit_completed AS DOUBLE)) / SUM(CAST(num_visit_booked AS DOUBLE)) AS vb2vc_rate
FROM dw_visit.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
JOIN dw_house.dim_house_entrance_history AS dim_h
  ON fv.sk_house_entrance = dim_h.sk_house_entrance
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '30' DAY
GROUP BY 1
ORDER BY vb DESC;
```

### 3. Visit finalization by demand (Visit contested Performance)

Identifies contested completed visits by demand grouping by channel (conventional vs IA).

```sql
SELECT
    pvd.channel,
    SUM(fv.num_visit_completed) AS vc_by_agent,
    SUM(fv.num_visit_unsuccessful_by_demand) AS vu_by_demand,
    SUM(CAST(fv.num_visit_unsuccessful_by_demand AS DOUBLE)) / SUM(CAST(fv.num_visit_completed AS DOUBLE)) AS vc_contested_rate
FROM dw_visits.fact_visits AS fv
JOIN dw_visit.dim_visit AS dv
  ON fv.sk_visit = dv.sk_visit
JOIN dw_visit.dim_post_visit_demand AS pvd
  ON fv.sk_post_visit_demand = pvd.sk_visit
WHERE dv.ts_visit >= CURRENT_DATE - INTERVAL '60' DAY
AND dv.is_visit_completed
GROUP BY 1
```
