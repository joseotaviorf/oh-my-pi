# Prospect (BP & TP)

## Ownership

**Data Owner:**
- philipp.margraf@quintoandar.com.br

**Data Steward:**
- rafaela.godoy@quintoandar.com.br

## Overview

**Prospect** is the umbrella demand entity for a user who becomes **active demand** on a property by booking a visit, submitting an offer, or talking to an agent. The same underlying status-transition logic produces two business-context-specific metrics:

- **Buyer Prospect (BP)** → Prospect activity where `business_context = 'sale'` (**For Sale only**).  
- **Tenant Prospect (TP)** → Prospect activity where `business_context = 'rent'` (**For Rent only**).

BP and TP are **not two different calculations** — they are the same New/Recovered Prospect logic, sliced by business context.

**Official source of truth: `metric_growth.growth_demand_performance_daily`.** This is the daily-grain mart behind the Growth Performance Tracking Superset dashboard. It carries `new_prospects` and `recovered_prospects` already computed. Official native segmentation columns (no joins required): `business_context`, `medium`, `operation_channel`, `referral_type`, `source`, `country_code`, and `city_group`. `source` is a first-class last-touch dimension on this table (the origin of the touchpoint, sibling of `medium`) — it is part of the supported cut set, not an optional extra. Aggregate by day, week, or month as needed.

**Official attribution model — last-touch, not n-touch.** Growth's Performance Tracking treats Prospect as a **last-touch** metric: a Prospect activation is credited to the single most recent touchpoint (medium / operation channel / referral type) in the user's history, not to every channel that touched the journey. The one exception is the **Direct** medium, which is only assigned when the user has **no other touchpoint at all**. n-touch (multi-touch) is a separate alternative view — see the BP n-touch reference doc — used to measure channel/partner participation beyond the official last-touch number; it does not apply to this table.

## Related Domain Entities

- FS Transact (For Sale)  
- FR Transact (For Rent)  
- Visits  
- BP n-touch (multi-touch attribution variant, For Sale)

## Glossary and Synonyms

- **Prospect** → the general entity: a user with active demand on a property.  
- **BP**, **Buyer Prospect** → Prospect where `business_context = 'sale'`.  
- **TP**, **Tenant Prospect** → Prospect where `business_context = 'rent'`.  
- **NBP / New Buyer Prospect**, **NTP / New Tenant Prospect** → `new_prospects` component.  
- **RBP / Recovered Buyer Prospect**, **RTP / Recovered Tenant Prospect** → `recovered_prospects` component.  
- **Last-touch (default attribution)** → the official Growth Performance Tracking model: every activation credited to the single most recent touchpoint. Contrast with **n-touch**, below.  
- **n-touch**, **multi-touch** → an alternative attribution model (BP n-touch reference doc) that credits every channel touched, not just the last one. Not used on this table.  
- **Direct** (`medium = 'Direct'`) → the one exception to last-touch: assigned only when the user has no other touchpoint at all in their history.  
- **TQC**, **Traz Quem Compra** (`referral_type`) → the 1P/3P broker/partner program that can originate a Prospect. See the BP n-touch doc for TQC 1P / TQC 3P / CQA definitions.

## Scope

**Included**: Prospect activations (New and Recovered) already computed on `metric_growth.growth_demand_performance_daily`, for both business contexts (`rent`, `sale`), broken down by day/week/month and by any of the native segmentation columns (`medium`, `operation_channel`, `referral_type`, `source`, `country_code`, `city_group`).

**Excluded**: any raw event-level re-derivation from upstream event tables — this document intentionally does not use `dw_growth.fact_demand_prospect_events` as a reporting source (see Calculation for why).

## Calculation

```
Prospects = New Prospects + Recovered Prospects
```

split per business context (BP for sale, TP for rent):

```sql
SUM(new_prospects)      AS new_prospects
SUM(recovered_prospects) AS recovered_prospects
SUM(new_prospects) + SUM(recovered_prospects) AS prospects
```

grouped by whatever period/dimension is needed, from `metric_growth.growth_demand_performance_daily`.

**Report the sum of New \+ Recovered as the headline figure**; New and Recovered are components, not separately reportable totals.

### Canonical Filter

Restrict to the two official business contexts (`rent` = TP, `sale` = BP) and the desired date range — `metric_growth.growth_demand_performance_daily` is already scoped to Prospect activations:

```sql
SELECT
    date_trunc('month', dt_event) AS month_start,
    CASE
      WHEN LOWER(business_context) = 'rent' THEN 'Rent'
      WHEN LOWER(business_context) = 'sale' THEN 'Sale'
    END AS business_context,
    SUM(new_prospects) AS new_prospects,
    SUM(recovered_prospects) AS recovered_prospects
FROM metric_growth.growth_demand_performance_daily
WHERE dt_event >= DATE '2026-03-01' AND dt_event < DATE '2026-09-01'
  AND LOWER(business_context) IN ('rent', 'sale')
GROUP BY 1, 2
```

### Nuances

| Nuance | Detail |
| :---- | :---- |
| Cross-source variance | A live re-derivation from event-level tables (e.g. `dw_growth.fact_demand_prospect_events`) differs marginally (≈0.02%–0.3%, validated 2026-09-18) from this mart, purely due to pipeline/grain differences between ETL jobs — **not** because New and Recovered overlap. New and Recovered are mutually exclusive buckets by construction. Use this mart as the single source of truth for Prospects reporting and validation. |
| Idle-period threshold (Recovery Rule) | A Prospect moves from active to churned, and later becomes eligible for Recovered, after a period with no touchpoint at all: **28 days for For Rent (TP)**, **90 days for For Sale (BP)**. This is resolved upstream into `new_prospects` / `recovered_prospects` — not something to recompute. |
| Attribution model | This mart reflects the **official last-touch** attribution — every activation credited to the single most recent touchpoint, with `Direct` as the no-touchpoint fallback. It does not carry the alternative n-touch (multi-touch) view — see the BP n-touch reference doc for that. |
| Native segmentation columns | `medium`, `operation_channel`, `referral_type`, `source`, `country_code`, `city_group` are all native on this table — no joins required. `source` is an officially supported last-touch cut (same grain as `medium`), not a derived/join-only field. |

## Dos and Don'ts

**Do:**

- Use `metric_growth.growth_demand_performance_daily` for any Prospects/BP/TP number — headline or segmented — aggregating `SUM(new_prospects)` / `SUM(recovered_prospects)` at the day/week/month grain needed.  
- Split BP vs TP via `business_context`.  
- Use `medium`, `operation_channel`, `referral_type`, `source`, `country_code`, `city_group` directly — no joins needed for any of them on this table.  
- Expect small (≈0.02%–0.3%) variance if a number is cross-checked against a different pipeline/table — that is a pipeline-grain artifact, not a data quality issue.

**Don't:**

- Don't rebuild Prospects from event-level tables for reporting or validation — this mart is the source of truth.  
- Don't attribute a fact-table-vs-mart variance to "the same prospect having multiple qualifying transitions" — New and Recovered are mutually exclusive by construction; that is not the source of any variance.

## Catalog

| Metric | Type |
| :---- | :---- |
| Buyer Prospect (BP) | Health Metric |
| Tenant Prospect (TP) | Health Metric |

## Golden Query

**Prospect volume (BP \+ TP), segmented by the official native cuts (`business_context`, `medium`, `operation_channel`, `referral_type`, `source`, `country_code`, `city_group`):**

```sql
SELECT
    date_trunc('month', dt_event) AS month_start,   -- swap for 'day' / 'week' as needed
    country_code,
    city_group,
    operation_channel,
    referral_type,
    CASE
      WHEN LOWER(business_context) = 'rent' THEN 'Rent'
      WHEN LOWER(business_context) = 'sale' THEN 'Sale'
    END AS business_context,
    medium,
    source,
    SUM(new_prospects) AS new_prospects,
    SUM(recovered_prospects) AS recovered_prospects,
    SUM(new_prospects) + SUM(recovered_prospects) AS prospects
FROM metric_growth.growth_demand_performance_daily
WHERE dt_event >= DATE '2026-03-01' AND dt_event < DATE '2026-09-01'
  AND LOWER(business_context) IN ('rent', 'sale')
GROUP BY 1,2,3,4,5,6,7,8
ORDER BY 1 DESC
```

Drop unused `GROUP BY` columns (e.g. down to just month \+ business\_context) for a headline check, or add `AND medium = '<value>'` / `AND source = '<value>'` to reproduce a specific medium / source / business-context cut.

Stable references: DataHub dataset `metric_growth.growth_demand_performance_daily` (produced by DAG `metric_growth__demand`); related domain context in `docs/llm_context/domain_entities/seo.md`.

## Technical Validation (Tars/DataHub \+ Trino) — 2026-09-18

Schema verified in DataHub (production): `metric_growth.growth_demand_performance_daily` exists, with no failing DQ assertions, `ts_load` from the day of validation. All official native segmentation columns (`business_context`, `medium`, `operation_channel`, `referral_type`, `source`, `country_code`, `city_group`) confirmed native on the table.

Query executed live on Trino (delta, data-prd), last 6 closed months (Mar–Aug 2026), Rent/Sale split:

| Month | Business Context | Prospects |
| :---- | :---- | ----: |
| 2026-03 | Rent | 153,676 |
| 2026-03 | Sale | 32,675 |
| 2026-08 | Rent | 146,768 |
| 2026-08 | Sale | 35,474 |

`medium = 'Placas'` check, August 2026: Rent 5,320 / Sale 1,264.

Compared against `metric_growth.growth_demand_performance_monthly` (same grain, aggregated) and against `dw_growth.fact_demand_prospect_events` (live re-derivation): difference ≤0.3% in every month tested — consistent with normal pipeline variance between tables, not a calculation error.  
