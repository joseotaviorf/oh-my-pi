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
| Consolidated **visit** view (final status, funnel metrics) | `dw_visits.fact_visits` |
| History of each individual **schedule** (reschedules/attempts) | `dw_visits.fact_visit_schedules` |
| Detailed visit attributes (source, cancel reason, context) | `dw_visits.dim_visit` |
| Confirmation details and lifecycle timestamps per schedule | `dw_visits.dim_visit_schedule` |
| Post-visit evaluations (feedback from demand) | `dw_visits.dim_post_visit_demand` |
| Property entrance and key management data | `dw_visits.fact_house_entrance` |

### The `dw_visits` building blocks

#### `fact_visits`

Daily **visit** grain: one row per consolidated visit.

| Topic | Fields |
|-------|--------|
| Keys | `sk_visit`, `sk_visitor`, `sk_house`, `sk_house_entrance` |
| Status | `visit_status`, `is_completed`, `is_cancelled`, `is_unsuccessful` |
| Funnel | `sk_funnel_proposal`, `sk_funnel_contract` |

#### `fact_visit_schedules`

Daily **schedule** grain: one row per appointment attempt.

| Topic | Fields |
|-------|--------|
| Keys | `sk_schedule`, `sk_visit`, `sk_broker` |
| Confirmation | `is_demand_confirmed`, `is_supply_confirmed`, `is_broker_confirmed` |
| Timing | `dt_schedule`, `tm_schedule`, `is_last_schedule` |

## Dos and Don'ts

**Do:**

- Use **`fact_visits`** for funnel conversion metrics (e.g., visits that turned into proposals).
- Use the same tables for both for rent and for sale business contexts.
- Always filter by **`is_last_schedule = TRUE`** in the schedules table if you want to see only the final/valid attempt for a visit.
- Join **`dim_post_visit_demand`** to understand why a completed visit did not generate a proposal (qualitative feedback).
- Check the **`visit_status`** to distinguish between "Completed" visits and "Unsuccessful" visits (where a visit was attempted but failed).
- Include a partition guard (e.g., `dt_visit >= CURRENT_DATE - INTERVAL '6' MONTHS`) to optimize query performance.

**Don't:**

- Don't count `sk_schedule` as unique visits; a user may reschedule the same visit 3 times, generating 3 schedules but only 1 `sk_visit`.
- Don't assume `visit_status = 'cancelled'` implies a system error; use `cancel_reason` to distinguish between demand-led, supply-led, or broker-led cancellations.
- Don't mix `house_entrance` data with visit status without validating if the entrance model was available at the time of the visit.

## Golden queries

### 1. Visit Booked to Visit Completed (VB2VC) Rate

The primary metric for understanding scheduling efficiency and completion.

```sql
SELECT 
    DATE_TRUNC('month', dt_visit) AS month_ref,
    SUM(num_visit_booked) AS total_visits_booked,
    SUM(num_visit_completed) AS completed_visits,
    SUM(num_visit_completed) / SUM(num_visit_booked) AS vb2vc_rate
FROM dw_visits.fact_visits
WHERE dt_visit >= CURRENT_DATE - INTERVAL '6' MONTHS
GROUP BY 1
ORDER BY 1 DESC;
```

### 2. Visits by Entrance Model (Access Performance)

Identifies which access methods (e.g., Broker keys vs. Concierge) lead to higher completion rates.

```sql
SELECT 
    dim_h.entrance_model,
    COUNT(DISTINCT f.sk_visit) AS total_visits,
    SUM(num_visit_completed) AS completed_visits,
    SUM(num_visit_unsuccessful) AS unsuccessful_visits
FROM dw_visits.fact_visits f
JOIN dw_visits.dim_house_entrance dim_h ON f.sk_house_entrance = dim_h.sk_house_entrance
WHERE f.dt_visit >= CURRENT_DATE - INTERVAL '30' DAYS
GROUP BY 1
ORDER BY total_visits DESC;
```