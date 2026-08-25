# Supply Pricing Score (Owner Activation H2 2026)

## Ownership

**Data Owner:**
- rosi.silva@quintoandar.com.br

**Data Steward:**
- carolina.almeida@quintoandar.com.br

## Overview

**Supply Pricing Score** is the official **price-only** competitiveness score (0–4 per listing × window) used in the **[Growth][OwnerActivation] Cockpit** for H2 2026 OKRs. Each listing gets a discrete score at publication and at cohort checkpoints (1w–8w) by comparing listed price to a CPS reference bound.

This metric is **related but not identical** to **Quality Pub / Quality 4Ws** in [`supply_quality_score.md`](supply_quality_score.md): Quality metrics combine **price score + easy entry** from `sandbox.listing_scores` on a **First Listing 1P** cohort from `2025-08-01`. Supply Pricing Score uses **only** the price component, broader listing categories, **1P + 3P**, and H2 2026 publication cohorts — with **RENT** scores pre-materialized in `sandbox.listing_score_pricing` and **SALE** scores computed in-query from `dw_listing` + CPS p70.

**Official OKR numbers:**

- **RENT:** `AVG(score_4w)` on matured 4-week cohorts (`is_matured_4w = TRUE`)
- **SALE:** `AVG(score_8w)` on matured 8-week cohorts (`is_matured_8w = TRUE`)

Aggregate by `week_pub` or `month_pub` (publication date). **Well priced** = score `4`; **overpriced** = score `< 4`.

**Applies to For Rent and For Sale (Brazil), 1P and 3P, First listing and Relisting/Recovered.**

## Related Domain Entities

- Pricing
- House and Listing

## Related Metric Entities

- Quality of Supply (Pricing Levers) — Pub & 4Ws — RENT combined price + easy entry; shares the price-score concept via `price_score_4w` in `sandbox.listing_scores`
- Owner Activation Listing Churn (H2 2026) — sibling KR2 in the same Cockpit dataset; see [`owner_activation_listing_churn.md`](owner_activation_listing_churn.md)

## Catalog

| Metric | Type |
| :---- | :---- |
| Pricing Score (RENT, 4w) | OKR |
| Pricing Score (SALE, 8w) | OKR |

## MBR

- Growth MBR

## Glossary and Synonyms

- **Pricing Score**, **price score**, **score de precificação** → this metric family (0–4 per listing/window)
- **Pricing Score OKR (RENT)** → `AVG(score_4w)` on matured cohorts
- **Pricing Score OKR (SALE)** → `AVG(score_8w)` on matured cohorts
- **score_pub**, **score at publication** → score at `dt_pub` (diagnostic; not the OKR headline for RENT/SALE above)
- **Well priced** → score = `4`
- **Overpriced** (in this framework) → score `< 4`
- **Quality 4Ws**, **Quality Pub** → different official metrics; see [`supply_quality_score.md`](supply_quality_score.md)

## Scope

**Included:**

- **SALE:** listings with `ts_first_publication` from `2026-01-01` through D-1 (`< CURRENT_DATE`), `price IS NOT NULL` on `dw_sale.dim_listing`
- **RENT:** `dw_rent.dim_house_listing` with `version > 0`, `listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')`, same publication window
- **1P and 3P** (`is_3p_supply` available for segmentation; Cockpit has no default channel filter)

**Excluded:**

- Listings outside the publication date window
- Immature cohorts when reporting OKR headline metrics (RENT 4w / SALE 8w require `is_matured_4w` / `is_matured_8w`)
- Quality Pub / 4Ws combined formula — use [`supply_quality_score.md`](supply_quality_score.md) for that OKR/dashboard

## Calculation

Per listing, per checkpoint window, assign an integer **price score** `0–4` from the ratio `listed_price / reference_bound` (only when `reference_bound > 0`).

### Score bands

**SALE** — reference = CPS **`suggested_upper_bound_price`** (p70) from `dw_listing.fact_price_suggested`:

| Ratio `price / ref_p70` | Score |
|-------------------------|-------|
| `< 1.05` | 4 |
| `< 1.10` | 3 |
| `< 1.20` | 2 |
| `< 1.30` | 1 |
| else | 0 |

**RENT** — reference = CPS **p90** bound (`upper_bound_limit` in the scoring pipeline). Bands (≤, not <):

| Ratio `price / ref_p90` | Score |
|-------------------------|-------|
| `<= 1.00` | 4 |
| `<= 1.15` | 3 |
| `<= 1.30` | 2 |
| `<= 1.45` | 1 |
| else | 0 |

RENT listing-level scores (`price_score_pub` … `price_score_8w`) are **pre-computed** in `sandbox.listing_score_pricing` (Ops, daily). SALE scores are built in the Owner Activation SQL path (same logic as Cockpit dataset).

### OKR aggregation

```
Pricing Score OKR (RENT) = AVG(score_4w)  WHERE is_matured_4w = TRUE
Pricing Score OKR (SALE) = AVG(score_8w)  WHERE is_matured_8w = TRUE
```

Group by `month_pub` or `week_pub` when trending. Default Cockpit analysis uses **closed cohorts** (matured windows) with publication date as the x-axis; cohort close date or uplift vs prior cohort are valid ad-hoc cuts — state the axis explicitly.

### Canonical Filter

**Publication cohort (both contexts):**

```sql
-- SALE
ts_first_publication >= DATE '2026-01-01'
AND ts_first_publication < CURRENT_DATE
AND price IS NOT NULL

-- RENT
version > 0
AND ts_publication >= DATE '2026-01-01'
AND ts_publication < CURRENT_DATE
AND listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')
```

**OKR headline (apply on top of listing-level scores):**

```sql
-- RENT OKR
is_matured_4w = TRUE   -- dt_cohort_4w < CURRENT_DATE

-- SALE OKR
is_matured_8w = TRUE   -- dt_cohort_8w < CURRENT_DATE
```

**Warning:** Using `AVG(score_pub)` as the OKR number, mixing immature cohorts into 4w/8w averages, or applying RENT band logic to SALE (or vice versa) will not match the Cockpit. Do not substitute Quality 4Ws for this OKR — different formula and cohort.

### Nuances

| Topic | Detail |
| :---- | :---- |
| **RENT scores** | Read `price_score_pub`, `price_score_1w` … `price_score_8w` from `sandbox.listing_score_pricing` — maintained daily by Ops; not in `bi-etl-ejuice` |
| **SALE scores** | Computed from `dw_listing.fact_price_changes` + `dim_pricing` (`is_last_price_of_day`) joined to `fact_price_suggested.suggested_upper_bound_price` at each cohort boundary |
| **Cohort windows** | `dt_cohort_Nw = dt_pub + N×7 days`; price snapshot = latest `is_last_price_of_day` row on or before boundary |
| **Maturity flags** | `is_matured_Nw = (dt_cohort_Nw < CURRENT_DATE)` |
| **1P / 3P** | `is_3p_supply` on listing dims; Cockpit includes both |
| **Targets in dataset** | Embedded constants: RENT `target_ps = 3.78`, SALE `target_ps = 3.08` — confirm against planning if comparing to official OKR target |

**Validation reference (March 2026, matured cohorts, 1P+3P):**

| Context | score_pub | OKR window |
|---------|-----------|------------|
| RENT | 3.34 | score_4w **3.59** |
| SALE | 2.48 | score_8w **2.91** |

## Dos and Don'ts

**Do:**

- Use **`AVG(score_4w)`** (RENT) and **`AVG(score_8w)`** (SALE) for OKR headline metrics on **matured** cohorts
- Filter publication cohort `>= 2026-01-01` and `< CURRENT_DATE`
- Segment with `is_3p_supply` when the question is 1P vs 3P
- Route **Quality Pub / 4Ws** questions to [`supply_quality_score.md`](supply_quality_score.md)
- For RENT listing scores, read **`sandbox.listing_score_pricing`** (not `sandbox.listing_scores` alone for this OKR path)

**Don't:**

- Don't equate this metric with **Quality 4Ws** — that is `(price_score_4w + easy_entry_4w) / count` on a narrower 1P FL cohort
- Don't report OKR on `score_pub` unless the question explicitly asks for publication-time score
- Don't use RENT p90 band logic on SALE (SALE uses p70 and `<` thresholds)
- Don't include immature weeks in OKR 4w/8w averages

## Golden Queries

Listing-level score construction mirrors the Owner Activation dataset (`krs_h2.sql` — SALE inline, RENT from `sandbox.listing_score_pricing`). Below: **official OKR aggregation** by publication month.

### Query 1 — Pricing Score OKR (RENT, monthly)

```sql
WITH rent_pub_cohort AS (
    SELECT
        sk_house_listing,
        CAST(ts_publication AS DATE) AS dt_pub,
        DATE_TRUNC('month', CAST(ts_publication AS DATE)) AS month_pub,
        CAST(ts_publication AS DATE) + INTERVAL '28' DAY AS dt_cohort_4w
    FROM dw_rent.dim_house_listing
    WHERE version > 0
      AND ts_publication >= DATE '2026-01-01'
      AND ts_publication < CURRENT_DATE
      AND listing_category_start IN ('First Listing', 'Re-Listing', 'Recovered')
),
rent_scores AS (
    SELECT
        c.sk_house_listing,
        c.month_pub,
        TRY_CAST(ps.price_score_4w AS DOUBLE) AS score_4w,
        c.dt_cohort_4w < CURRENT_DATE AS is_matured_4w
    FROM rent_pub_cohort AS c
    INNER JOIN sandbox.listing_score_pricing AS ps
        ON ps.sk_house_listing = c.sk_house_listing
)
SELECT
    month_pub,
    AVG(score_4w) AS pricing_score_okr_rent_4w
FROM rent_scores
WHERE is_matured_4w = TRUE
GROUP BY month_pub
ORDER BY month_pub
```

### Query 2 — Pricing Score OKR (SALE, monthly)

SALE requires the full price + CPS p70 scoring chain from the Cockpit SQL. Reproduce `sale_pub_cohort` → `sale_scored_price` → `sale_scored_ref` → `score_8w` from `krs_h2.sql`, then aggregate:

```sql
-- After building sale_final (or equivalent) with score_8w and is_matured_8w:
SELECT
    month_pub,
    AVG(score_8w) AS pricing_score_okr_sale_8w
FROM sale_final
WHERE is_matured_8w = TRUE
GROUP BY month_pub
ORDER BY month_pub
```

## Superset Golden Assets

- **[Growth][OwnerActivation] Cockpit Dashboard** — Owner Activation KPI cockpit (Pricing Score + Churn). Reference only for navigation. URN: `urn:li:dashboard:(superset,dashboard.4240)`
- **[OwnerActivation] KRs - H2 2026 - SALE & RENT [Growth]** — canonical virtual dataset for listing-level cohort scores (union SALE + RENT). RENT reads `sandbox.listing_score_pricing`; SALE scores computed in SQL. URN: `urn:li:dataset:(urn:li:dataPlatform:superset,22993,PROD)`
