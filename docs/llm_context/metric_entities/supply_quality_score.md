# Quality of Supply (Pricing Levers) — Pub & 4Ws

## Overview

**Quality Pub** and **Quality 4Ws** measure the competitiveness and health of a listing's pricing (pricing levers) within the For Rent (Locação) vertical in Brazil (BR).

- **Quality Pub (at Publication):** Measures the listing's pricing attractiveness at "day zero" (the exact moment of its first publication).
- **Quality 4Ws (after 4 Weeks):** Measures the resilience and evolution of the pricing attractiveness after a 28-day cohorted window, reflecting how the price performs and sustains itself against market demand.

The metrics support segmentation by temporal views (Monthly/L5M and Weekly/Maturing) and apply strictly to proprietary channels (1P) in the official dashboard baseline.

**Exists exclusively for For Rent (Brazil).**

## Related Business Entities

- Supply
- Pricing

## Glossary and Synonyms

- **Quality Pub**, **Quality of Supply at Publication**, **Quality at Publication**, **Qualidade de Supply na Publicação** → Quality Pub
- **Quality 4Ws**, **Quality of Supply after 4 Weeks**, **Quality at 28 days**, **Qualidade de Supply na Coorte de 4 Semanas** → Quality 4Ws

## Scope

**Included:** Unique properties published as First Listing in Brazil (`country_code = 'BR'`), belonging to the For Rent vertical (`nm_business_context = 'RENT'`), with publication dates from `2025-08-01` onwards. Only proprietary acquisition channels (1P) are included in the baseline dashboard numbers.

**Excluded:** Properties published before `2025-08-01`, relistings (non-First Listings), and properties acquired via partner channels (3P/Rede).

**4Ws specific exclusion:** Listings that have not yet completed their 28-day maturation period (`time_completed_4w = FALSE`) are strictly excluded to avoid pulling the average down with incomplete data.

## Calculation

The final metric is not a simple division of scores, but rather the **average combined score per listing**. It calculates the sum of the Price Score and Easy Entry Score, divided by the distinct count of listings in that cohort.

The correct calculation is:

```
Quality Pub = (SUM(price_score_pub) + SUM(easy_entry_pub)) / COUNT(DISTINCT sk_house_listing)

Quality 4Ws = (SUM(price_score_4w) + SUM(easy_entry_4w)) / COUNT(DISTINCT sk_house_listing)
```

where `price_score_*` and `easy_entry_*` come from `sandbox.listing_scores`, and each listing contributes once per cohort via `sk_house_listing`.

The dashboard formats this output to the Brazilian locale (comma as the decimal separator).

### Canonical Filter

Base rules (apply to both metrics):

Apply on `dw_rent.dim_house_listing`, `sandbox.listing_scores`, and `base_supply`:

```sql
dhl.listing_category_start = 'First Listing'
AND date(qs.listing_start_dt) >= date('2025-08-01')
AND base_supply.is_3p_fr = '1P'
AND NOT (EXTRACT(MONTH FROM qs.listing_start_dt) = 8 AND hdi4.rent IS NULL)  -- August Bug
```

Quality 4Ws strict requirement:

```sql
AND qs.time_completed_4w = TRUE
```

**Warning:** Filtering only on First Listing and publication date without the 1P channel filter, August Bug exclusion, or (for 4Ws) the maturation flag will include listings outside the official dashboard universe and deflate or inflate recent cohort performance.

### Nuances

**1P / 3P channel classification:** Evaluated retroactively using `dw_growth.obt_supply`. Specific rules using `planning_operation`, date windows, `sk_user_conversion` / `sk_user_affiliate` IDs, and `nm_agent` are used to isolate 3P REDE and 3P Operations. Everything else defaults to 1P.

**The "August Bug":** Listings published in August 2025 suffered a bug where the rent metric returned NULL. These records must be filtered out via `NOT (EXTRACT(MONTH FROM qs.listing_start_dt) = 8 AND hdi4.rent IS NULL)` to match the GSheets dashboard.

**4Ws maturation lock:** The dashboard visually hides immature weeks, but the SQL must actively filter them using `time_completed_4w = TRUE`; otherwise the denominator will artificially deflate the recent month's performance.

| Table | Application / Filter |
| :---- | :---- |
| `sandbox.listing_scores` | Core: provides `price_score`, `easy_entry`, and `time_completed_4w` flags |
| `dw_rent.dim_house_listing` | Dimensions: filters `listing_category_start IN ('First Listing')` |
| `dw_growth.obt_supply` | Attribution: determines 1P vs 3P origin; `cd_funnel_step = 'first_listing'` |
| `datalake_rental_historical_follow_up.house_listings_daily_info` | Auditing: captures the exact snapshot at D0 to handle the August `rent IS NULL` bug |

**Join key:** Match `dhl.id_house = base_supply.sk_house` for channel attribution; join `hdi4` on `hdi4.id_house_listing = dhl.sk_house_listing AND hdi4.dt_day = date(dhl.ts_listing_version_start)` for the August Bug filter.

**Fallback:** When building `base_supply` for 4Ws, deduplicate to one row per house using the latest `obt.date` (see Golden Queries).

## Dos and Don'ts

**Do:**

- Use `(SUM + SUM) / COUNT(DISTINCT)` to find the accurate score per listing
- Apply the 1P filter (`is_3p_fr = '1P'`) when matching the official dashboard baseline
- Deduplicate `base_supply` with `ROW_NUMBER()` instead of `SELECT DISTINCT` when preparing the CTE to prevent Cartesian explosions and memory bottlenecks
- Filter `time_completed_4w = TRUE` when analyzing the 4Ws metric to respect the 28-day maturation window

**Don't:**

- Use a simple average of averages (e.g., averaging the metric across `city_group` rows); always recalculate the weighted sum and divide by the total listings for aggregate views
- Join demand events (`fact_rent_demand_events`) or status cohort logic if the end goal is strictly the top-level pricing score, as it drastically increases query runtime without altering the calculation

## Golden Queries

### 1. Quality Pub (Momento Zero / D0) — Mensal e Semanal

Consolidated query generating both Monthly (L5M) and Weekly (Maturing) views for the publication D0 snapshot. The `base_data` CTE applies the canonical filter; aggregation is exclusive to this metric.

```sql
WITH base_supply AS (
    SELECT DISTINCT
        obt.date,
        obt.sk_house,
        dhl.sk_house_listing,
        upper(obt.planning_cluster) AS planning_cluster,
        upper(obt.planning_operation) AS planning_operation,
        upper(obt.planning_conversion) AS planning_conversion,
        CASE
            WHEN upper(obt.planning_operation) = 'REDE' THEN '3P REDE'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.nm_business_context = 'RENT'
                 AND obt.sk_user_conversion IN (8919771, 11299701, 6001450) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.nm_business_context = 'RENT'
                 AND lower(obt.nm_agent) IN ('ciq_pj', '3p_fr') THEN '3P Operations'
            ELSE '1P'
        END AS is_3p_fr
    FROM dw_growth.obt_supply obt
    LEFT JOIN dw_rent.dim_house_listing dhl
        ON dhl.id_house = obt.sk_house
        AND dhl.version = 0
        AND obt.nm_business_context = 'RENT'
    WHERE obt.nm_business_context = 'RENT'
      AND obt.country_code = 'BR'
      AND obt.date < current_date
      AND obt.cd_funnel_step = 'first_listing'
),
base_data AS (
    SELECT
        CAST(qs.listing_start_mth AS DATE) AS listing_start_mth,
        CAST(qs.listing_start_week AS DATE) AS listing_start_week,
        qs.sk_house_listing,
        qs.price_score_pub,
        qs.easy_entry_pub
    FROM sandbox.listing_scores qs
    LEFT JOIN dw_rent.dim_house_listing AS dhl
        ON qs.sk_house_listing = dhl.sk_house_listing
    LEFT JOIN base_supply
        ON dhl.id_house = base_supply.sk_house
    WHERE date(qs.listing_start_dt) >= date('2025-08-01')
      AND dhl.listing_category_start IN ('First Listing')
      AND base_supply.is_3p_fr = '1P'
),
agrupamento_mensal AS (
    SELECT
        '1 - Mensal (L5M)' AS visao_temporal,
        listing_start_mth AS data_referencia,
        1.000 * (SUM(price_score_pub) + SUM(easy_entry_pub))
            / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS metric_quality_pub
    FROM base_data
    GROUP BY 1, 2
),
agrupamento_semanal AS (
    SELECT
        '2 - Semanal (L4W/Maturing)' AS visao_temporal,
        listing_start_week AS data_referencia,
        1.000 * (SUM(price_score_pub) + SUM(easy_entry_pub))
            / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS metric_quality_pub
    FROM base_data
    GROUP BY 1, 2
)
SELECT * FROM agrupamento_mensal
UNION ALL
SELECT * FROM agrupamento_semanal
ORDER BY visao_temporal, data_referencia
```

### 2. Quality 4Ws (Coorte de 28 Dias) — Mensal

Monthly aggregate view accounting for cohort maturation and deduplicated supply attribution. The August Bug filter and `time_completed_4w` requirement are exclusive to this metric.

```sql
WITH base_supply_ranked AS (
    SELECT
        obt.sk_house,
        upper(obt.planning_cluster) AS planning_cluster,
        upper(obt.planning_operation) AS planning_operation,
        upper(obt.planning_conversion) AS planning_conversion,
        CASE
            WHEN upper(obt.planning_operation) = 'REDE' THEN '3P REDE'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.nm_business_context = 'RENT'
                 AND obt.sk_user_conversion IN (8919771, 11299701, 6001450) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.date <= DATE '2025-11-18'
                 AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994) THEN '3P Operations'
            WHEN obt.date >= DATE '2025-09-01'
                 AND obt.nm_business_context = 'RENT'
                 AND lower(obt.nm_agent) IN ('ciq_pj', '3p_fr') THEN '3P Operations'
            ELSE '1P'
        END AS is_3p_fr,
        ROW_NUMBER() OVER (PARTITION BY obt.sk_house ORDER BY obt.date DESC) AS rn
    FROM dw_growth.obt_supply obt
    WHERE obt.nm_business_context = 'RENT'
      AND obt.country_code = 'BR'
      AND obt.cd_funnel_step = 'first_listing'
      AND obt.date >= DATE '2025-06-01'
),
base_supply AS (
    SELECT sk_house, planning_cluster, planning_operation, planning_conversion, is_3p_fr
    FROM base_supply_ranked
    WHERE rn = 1
),
base_data AS (
    SELECT
        CAST(qs.listing_start_mth AS DATE) AS listing_start_mth,
        qs.sk_house_listing,
        qs.price_score_4w,
        qs.easy_entry_4w
    FROM sandbox.listing_scores qs
    INNER JOIN dw_rent.dim_house_listing AS dhl
        ON qs.sk_house_listing = dhl.sk_house_listing
        AND dhl.listing_category_start IN ('First Listing')
    INNER JOIN base_supply bs
        ON dhl.id_house = bs.sk_house
        AND bs.is_3p_fr = '1P'
    LEFT JOIN datalake_rental_historical_follow_up.house_listings_daily_info hdi4
        ON hdi4.id_house_listing = dhl.sk_house_listing
        AND hdi4.dt_day = date(dhl.ts_listing_version_start)
        AND hdi4.dt_day >= date('2025-08-01')
    WHERE date(qs.listing_start_dt) >= date('2025-08-01')
      AND qs.time_completed_4w = TRUE
      AND NOT (EXTRACT(MONTH FROM qs.listing_start_dt) = 8 AND hdi4.rent IS NULL)
),
agrupamento_mensal AS (
    SELECT
        '1 - Mensal (L5M)' AS visao_temporal,
        listing_start_mth AS data_referencia,
        1.000 * (SUM(price_score_4w) + SUM(easy_entry_4w))
            / NULLIF(COUNT(DISTINCT sk_house_listing), 0) AS metric_quality_4ws
    FROM base_data
    GROUP BY 1, 2
)
SELECT *
FROM agrupamento_mensal
ORDER BY data_referencia
```
