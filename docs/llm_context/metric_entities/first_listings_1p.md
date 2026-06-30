# FL (First Listings) 

## Overview

**FL (First Listings)** is the count of unique properties or listings published for the first time on the platform within a selected period. It is a leading indicator of new inventory health (supply), measuring acquisition performance across proprietary channels (1P) and partner channels (3P/Rede).

The metric supports segmentation by **supply source** (1P vs 3P) and by **business context** (For Rent vs For Sale), each with distinct table sources and classification logic.

**Applies to both For Rent (Locação) and For Sale (Vendas) verticals, Brazil (BR).**

## Related Business Entities

- Supply

## DataHub Catalog

- **This metric's data product**: `urn:li:dataProduct:first-listings-1p`
- **Upstream business entity data product**: `urn:li:dataProduct:supply`

## Glossary and Synonyms

- **FL**, **First Listing**, **First Listings**, **novas publicações**, **anúncios publicados pela primeira vez**, **volume de FL** → total first listings (all channels)
- **FL 1P**, **First Listings 1P**, **first listings proprietários** → first listings from proprietary channels only
- **FL 3P**, **First Listings 3P**, **first listings parceiros**, **first listings rede** → first listings from partner channels (BSP, Organic/Rede)

## Scope

**Included**: unique properties first published in Brazil (`country_code = 'BR'`) within the target city groups: RMSP, Rio de Janeiro, Porto Alegre, Campinas, Belo Horizonte, Brasília, Curitiba, and Goiânia.

**Excluded**: properties outside the focus city groups; for For Rent, listings with publication dates on or after the execution date (`current_date`).

## Calculation

The count is a `COUNT(DISTINCT sk_house_listing)` — one first listing per unique property/listing key. The For Sale and For Rent branches use different source tables and classification logic, then UNION into a single result set.

```
FL = COUNT(DISTINCT sk_house_listing)
```

Segment by `nm_supply_source` for 1P vs 3P, or by `business_context` for For Rent vs For Sale.

### Canonical Filter

**For Sale:**

```sql
-- dw_sale.fact_listings + dim_listing + dim_region + fact_daily_ongoing_listing
dr.country_code = 'BR'
AND dr.city_group IN ('RMSP', 'Rio de Janeiro', 'Porto Alegre', 'Campinas',
                      'Belo Horizonte', 'Brasília', 'Curitiba', 'Goiânia')
AND fdol.sk_snapshot_date = fl.sk_first_publication_date
```

**For Rent:**

```sql
-- dw_rent.dim_house_listing + fact_house_listings + dim_region
dhl.country_code = 'BR'
AND dhl.listing_category_start = 'First Listing'
AND CAST(dhl.ts_publication AS DATE) < CURRENT_DATE
AND dr.city_group IN ('RMSP', 'Rio de Janeiro', 'Porto Alegre', 'Campinas',
                      'Belo Horizonte', 'Brasília', 'Curitiba', 'Goiânia')
```

**Warning**: omitting `city_group` includes all Brazilian cities, producing numbers that do not match the official corporate metric which is scoped to the eight focus city groups.

### Nuances

**1P / 3P channel classification (For Sale):** determined by `dw_sale.dim_listing.is_3p_supply`. When `TRUE`, the listing is 3P; when `FALSE`, it is 1P.

**1P / 3P channel classification (For Rent):** uses a deduplication logic (`ROW_NUMBER()`) across two 3P sources, prioritizing **3P - BSP** (from `dw_3p_supply.fact_lead_3p_flows`) over **3P - Organic** (from `dw_growth.obt_supply` where `planning_conversion = 'Rede'`). Properties not matched by either source default to 1P.

| Source | Table | Filter |
|---|---|---|
| 3P - BSP | `dw_3p_supply.fact_lead_3p_flows` | `business_context = 'RENT'` AND `ts_business_context_created >= DATE '2026-02-18'` AND `ts_first_listing IS NOT NULL` |
| 3P - Organic | `dw_growth.obt_supply` | `date >= DATE '2025-09-01'` AND `nm_business_context = 'RENT'` AND `cd_funnel_step = 'first_listing'` AND `planning_conversion = 'Rede'` |

**Operation classification (`one_level_deeper`):**

- **For Sale**: operations simplified to IS (Outbound, Inbound, Capta Aí) or Other.
- **For Rent**: specific rules by user conversion/affiliate IDs and agents (`ciq_pj`, `3p_fr`) from retroactive 2025 dates classify the channel as Rede, plus isolation of the Reprocessamento cluster.

**High-ticket flag (`is_ht`)**: For Sale only — `sale_price >= 1,000,000` marks a listing as high-ticket.

**Timezone adjustment**: load timestamps use `CURRENT_TIMESTAMP - INTERVAL '3' HOUR` for Brasília time (BRT).

**Date dimension**: the reference query joins `sandbox.summary_date_dimensions` for WTD/MTD/YTD flags, `week_start`, `month_start`, `year_quarter`. For ad-hoc analysis, `DATE_TRUNC` on the publication date can replace this join.

## Dos and Don'ts

**Do:**

- Always filter by the eight focus `city_group` values and `country_code = 'BR'`
- Use `COUNT(DISTINCT sk_house_listing)` as the grain — one count per unique listing
- Apply the 3P dedup logic (BSP priority over Organic) before classifying For Rent listings as 1P
- For For Sale, join `fact_daily_ongoing_listing` with `sk_snapshot_date = sk_first_publication_date` to get the listing state at first publication
- For For Rent, filter `listing_category_start = 'First Listing'` and `ts_publication < CURRENT_DATE`

**Don't:**

- Don't omit `city_group` — the corporate metric is scoped to eight city groups, not all of Brazil
- Don't use `COUNT(*)` instead of `COUNT(DISTINCT sk_house_listing)` — JOINs with `obt_supply` and channel tables can multiply rows
- Don't mix For Sale and For Rent in the same branch — they use different source tables and classification logic
- Don't hardcode the 3P user IDs for Rede classification without the date-window guards (the rules are time-bounded)

## Golden Queries

The base CTE builds a unified wide table with both For Sale and For Rent first listings, including supply source classification, operation breakdown, and date dimension attributes. The final SELECT is swapped depending on the desired aggregation.

### Base CTE (For Sale branch)

Identifies distinct first-published houses from `dw_sale.fact_listings`, classifies 1P/3P via `dim_listing.is_3p_supply`, and enriches with supply funnel attributes from `dw_growth.obt_supply`.

### Base CTE (For Rent branch)

Identifies first listings from `dw_rent.dim_house_listing` where `listing_category_start = 'First Listing'`, classifies 1P/3P via the BSP/Organic dedup logic, and enriches with supply funnel and operation attributes.

### Full reference query

```sql
WITH date_dim AS (
    SELECT *
    FROM sandbox.summary_date_dimensions
),

aux AS (
    SELECT DISTINCT
        fl.sk_house,
        fl.sk_region,
        dr.city_group,
        dr.country_code,
        CASE WHEN dl.is_3p_supply THEN 1 ELSE 0 END AS is_3p_supply,
        fl.sk_first_publication_date,
        fdol.sale_price
    FROM dw_sale.fact_listings AS fl
    INNER JOIN dw_sale.dim_listing AS dl
        ON dl.sk_sale_listing = fl.sk_sale_listing
    INNER JOIN dw_public.dim_region AS dr
        ON dr.sk_region = fl.sk_region
    INNER JOIN dw_sale.fact_daily_ongoing_listing AS fdol
        ON fdol.sk_sale_listing = fl.sk_sale_listing
        AND fdol.sk_snapshot_date = fl.sk_first_publication_date
    WHERE
        dr.city_group IN (
            'RMSP', 'Rio de Janeiro', 'Porto Alegre', 'Campinas',
            'Belo Horizonte', 'Brasília', 'Curitiba', 'Goiânia'
        )
),

fl_3p_fr_organic AS (
    SELECT
        obt.sk_house,
        obt.date AS dt_first_listing,
        '3P - Organic' AS channel
    FROM dw_growth.obt_supply AS obt
    WHERE
        obt.date >= DATE '2025-09-01'
        AND obt.nm_business_context = 'RENT'
        AND obt.cd_funnel_step = 'first_listing'
        AND obt.planning_conversion = 'Rede'
),

listing_modelo_supply AS (
    SELECT DISTINCT
        sk_house,
        DATE_TRUNC('day', ts_first_listing) AS dt_first_listing,
        '3P - BSP' AS channel
    FROM dw_3p_supply.fact_lead_3p_flows
    WHERE
        business_context = 'RENT'
        AND ts_business_context_created >= DATE '2026-02-18'
        AND ts_first_listing IS NOT NULL
),

unioned AS (
    SELECT * FROM fl_3p_fr_organic
    UNION ALL
    SELECT * FROM listing_modelo_supply
),

dedup AS (
    SELECT
        sk_house,
        dt_first_listing,
        channel,
        ROW_NUMBER() OVER (
            PARTITION BY sk_house
            ORDER BY
                CASE
                    WHEN channel = '3P - BSP' THEN 1
                    WHEN channel = '3P - Organic' THEN 2
                    ELSE 3
                END,
                dt_first_listing ASC
        ) AS rn
    FROM unioned
),

final_3p AS (
    SELECT DISTINCT
        dhl.id_house,
        COALESCE(channel_3p.channel, '1P') AS nm_supply_source
    FROM dw_rent.dim_house_listing AS dhl
    LEFT JOIN dedup AS channel_3p
        ON dhl.id_house = channel_3p.sk_house
        AND channel_3p.rn = 1
    WHERE dhl.is_for_rent = TRUE
),

final AS (
    SELECT
        dt.is_wtd,
        dt.is_mtd,
        dt.is_ytd,
        dt.is_current_month,
        dt.is_current_week,
        dt.is_current_year,
        dt.date,
        dt.week_start,
        dt.month_start,
        dt.year_quarter,
        dt.year,
        aux.sk_region,
        aux.country_code,
        UPPER(aux.city_group) AS city_group,
        CASE
            WHEN obt.planning_operation IN ('Outbound', 'Inbound', 'Capta Aí') THEN 'IS'
            WHEN obt.planning_operation NOT IN ('Outbound', 'Inbound', 'Capta Aí', 'CIQ', 'Rede', 'FSS') THEN 'Other'
            ELSE obt.planning_operation
        END AS one_level_deeper,
        obt.planning_cluster,
        obt.planning_conversion,
        obt.company_report_origin,
        'For Sale' AS business_context,
        CASE
            WHEN aux.is_3p_supply = 1 THEN '3P'
            WHEN aux.is_3p_supply = 0 THEN '1P'
            ELSE 'NA'
        END AS nm_supply_source,
        'FL' AS metric_name,
        aux.sk_house AS sk_house_listing,
        aux.sk_house AS sk_house,
        aux.sale_price,
        CASE WHEN aux.sale_price >= 1000000 THEN 1 ELSE 0 END AS is_ht,
        obt.is_hybrid_listing,
        CURRENT_TIMESTAMP - INTERVAL '3' HOUR AS ts_load
    FROM aux
    INNER JOIN date_dim AS dt
        ON CAST(DATE_PARSE(CAST(aux.sk_first_publication_date AS VARCHAR), '%Y%m%d') AS DATE) = dt.date
    LEFT JOIN dw_growth.obt_supply AS obt
        ON obt.sk_house = aux.sk_house
        AND obt.cd_funnel_step = 'first_listing'
        AND obt.nm_business_context = 'SALE'
    WHERE
        aux.country_code = 'BR'
        AND dt.date > DATE '2026-01-01'

    UNION ALL

    SELECT
        dd.is_wtd,
        dd.is_mtd,
        dd.is_ytd,
        dd.is_current_month,
        dd.is_current_week,
        dd.is_current_year,
        dd.date,
        dd.week_start,
        dd.month_start,
        dd.year_quarter,
        dd.year,
        fhl.sk_region,
        dr.country_code,
        UPPER(dr.city_group) AS city_group,
        CASE
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.date <= DATE '2025-11-18'
                AND obt.nm_business_context = 'RENT'
                AND obt.sk_user_conversion IN (8919771, 11299701, 6001450)
                THEN 'Rede'
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.date <= DATE '2025-11-18'
                AND obt.nm_business_context = 'RENT'
                AND obt.sk_user_affiliate IN (12306405, 14046860, 14053116, 14046994, 14217303, 14294994)
                THEN 'Rede'
            WHEN obt.date >= DATE '2025-09-01'
                AND obt.nm_business_context = 'RENT'
                AND LOWER(obt.nm_agent) IN ('ciq_pj', '3p_fr')
                THEN 'Rede'
            WHEN UPPER(obt.planning_cluster) = 'REPROCESSAMENTO' THEN 'Reprocessamento'
            WHEN obt.planning_operation NOT IN ('FSS', 'Outbound', 'Capta Aí', 'Rede', 'Inbound', 'PP Multi', 'CIQ') THEN 'Other'
            ELSE obt.planning_operation
        END AS one_level_deeper,
        obt.planning_cluster,
        obt.planning_conversion,
        obt.company_report_origin,
        'For Rent' AS business_context,
        channel_3p.nm_supply_source,
        'FL' AS metric_name,
        dhl.sk_house_listing AS sk_house_listing,
        dhl.id_house AS sk_house,
        NULL AS sale_price,
        NULL AS is_ht,
        obt.is_hybrid_listing,
        CURRENT_TIMESTAMP - INTERVAL '3' HOUR AS ts_load
    FROM date_dim AS dd
    LEFT JOIN dw_rent.dim_house_listing AS dhl
        ON dd.date = CAST(dhl.ts_publication AS DATE)
    LEFT JOIN dw_growth.obt_supply AS obt
        ON dhl.id_house = obt.sk_house
        AND obt.cd_funnel_step = 'first_listing'
        AND obt.nm_business_context = 'RENT'
    LEFT JOIN dw_datamarts.affiliates_clusters AS ac
        ON ac.sk_user = obt.sk_user_affiliate
        AND ac.year_month = obt.year_month
    LEFT JOIN dw_rent.fact_house_listings AS fhl
        ON dhl.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN dw_public.dim_region AS dr
        ON fhl.sk_region = dr.sk_region
    LEFT JOIN final_3p AS channel_3p
        ON channel_3p.id_house = dhl.id_house
    WHERE
        dhl.country_code = 'BR'
        AND dd.date > DATE '2026-01-01'
        AND dd.date < CURRENT_DATE
        AND dhl.listing_category_start = 'First Listing'
),

tb_fl AS (
    SELECT
        act.is_wtd,
        act.is_mtd,
        act.is_ytd,
        act.is_current_month,
        act.is_current_week,
        act.is_current_year,
        act.date,
        act.week_start,
        act.month_start,
        act.year_quarter,
        act.year,
        act.country_code,
        act.city_group,
        act.one_level_deeper,
        act.planning_cluster,
        act.planning_conversion,
        act.company_report_origin,
        act.business_context,
        act.nm_supply_source,
        act.metric_name,
        act.is_ht,
        COUNT(DISTINCT act.sk_house_listing) AS actual
    FROM final AS act
    GROUP BY
        act.is_wtd, act.is_mtd, act.is_ytd,
        act.is_current_month, act.is_current_week, act.is_current_year,
        act.date, act.week_start, act.month_start, act.year_quarter, act.year,
        act.country_code, act.city_group, act.one_level_deeper,
        act.planning_cluster, act.planning_conversion, act.company_report_origin,
        act.business_context, act.nm_supply_source, act.metric_name, act.is_ht
)
```

### Extraction: FL 1P by week (For Rent)

```sql
-- Uses base CTE above (tb_fl)
SELECT
    week_start,
    SUM(actual) AS fl_1p
FROM tb_fl
WHERE business_context = 'For Rent'
    AND nm_supply_source = '1P'
GROUP BY week_start
ORDER BY week_start
```

### Extraction: FL total by week and business context

```sql
-- Uses base CTE above (tb_fl)
SELECT
    week_start,
    business_context,
    SUM(actual) AS fl
FROM tb_fl
GROUP BY week_start, business_context
ORDER BY week_start, business_context
```

### Extraction: FL by supply source and business context (monthly)

```sql
-- Uses base CTE above (tb_fl)
SELECT
    month_start,
    business_context,
    nm_supply_source,
    SUM(actual) AS fl
FROM tb_fl
GROUP BY month_start, business_context, nm_supply_source
ORDER BY month_start, business_context, nm_supply_source
```

### Extraction: FL 1P by operation (For Sale)

```sql
-- Uses base CTE above (tb_fl)
SELECT
    week_start,
    one_level_deeper,
    SUM(actual) AS fl_1p
FROM tb_fl
WHERE business_context = 'For Sale'
    AND nm_supply_source = '1P'
GROUP BY week_start, one_level_deeper
ORDER BY week_start, one_level_deeper
```

## Superset Golden Assets

- **[Growth][Supply] Executive Dashboard - First Listings** — canonical Superset dataset for first listings analysis segmented by business context, supply source, city group, and operation. URN: `urn:li:dataset:(urn:li:dataPlatform:superset,8916,PROD)`
