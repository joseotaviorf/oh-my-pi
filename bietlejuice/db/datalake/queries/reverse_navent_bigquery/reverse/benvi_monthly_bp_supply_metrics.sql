WITH dimension_period AS (
    SELECT DISTINCT
        year, 
        month_start,
        month_end
    FROM 
        dw_public.dim_date
    WHERE
        -- Start date 2022-06-01 based on Benvi's launch on Mexico
        date BETWEEN DATE('2022-06-01') AND DATE_ADD(CURRENT_DATE, 30) 
),
mexico_regions AS (
    SELECT
        sk_region,
        id_country,
        country_name,
        country_code,
        city_group
    FROM
        dw_public.dim_region
    WHERE
        id_country = 2
),
mexico_listing_flows AS (
    SELECT
        fhlf.sk_lead,
        fhlf.sk_lead_date,
        fhlf.sk_region,
        fhlf.mkt_origin,
        fhlf.mkt_channel
    FROM
        dw_public.fact_house_listing_flows AS fhlf
    WHERE
        fhlf.sk_lead_date >= 20220601
        AND fhlf.country_code = 'MX'
),
dimension_region AS (
    SELECT DISTINCT
        country_name,
        city_group
    FROM 
        mexico_regions
),
dimensions AS (
    SELECT *
    FROM 
        dimension_period
    CROSS JOIN 
        dimension_region
),
supply_funnel AS (
    SELECT 
        DATE_TRUNC('month', date) AS month_start,
        LAST_DAY(date) AS month_end,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        SUM(leads) AS leads,
        SUM(prospects) AS prospects,
        SUM(qualifieds) AS qualifieds,
        SUM(opportunities) AS opportunities,
        SUM(first_listings) AS first_listings
    FROM 
        dw_datamarts_growth_cross.unique_supply_events_funnel 
    WHERE
        origin_table = 'Rent'    
    GROUP BY 1, 2, 3, 4, 5
),
supply_funnel_targets AS (
    SELECT
        DATE_TRUNC('month', DATE(dt_target)) AS month_start,
        city_group,
        CASE 
            WHEN supply_origin = 'Organic traffic' THEN 'Organic'
            WHEN supply_origin = 'Landing page - PWA' AND supply_channel LIKE '%Paid%' THEN 'Paid' 
            WHEN supply_origin = 'Refiere y Gana' THEN 'Indica Aí - General'
            WHEN supply_origin = 'CIB' THEN 'CIQ'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS supply_channel,
        CASE 
            WHEN supply_origin IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN supply_origin = 'Refiere y Gana' THEN 'Indica Aí - General'
            WHEN supply_origin = 'CIB' THEN 'CIQ'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS supply_origin,
        SUM(CAST(NULLIF(prospects,'') AS REAL)) AS prospects,
        SUM(CAST(NULLIF(qualifieds,'') AS REAL)) AS qualifieds,
        SUM(CAST(NULLIF(opportunities,'') AS REAL)) AS opportunities,
        SUM(CAST(NULLIF(first_listings,'') AS REAL)) AS first_listings
    FROM 
        datalake_gsheets_clean.mexico_supply_targets_2022
    GROUP BY 1, 2, 3, 4
),
supply_costs_targets AS (
    SELECT
        DATE_TRUNC('month', dt_week) AS month_start,
        city_group,
        CASE 
            WHEN planning_mkt_level3 in ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_origin,
        CASE 
            WHEN planning_mkt_level3 = 'Landing page - PWA' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Organic traffic' THEN 'Organic'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_channel,
        SUM(budget) AS budget_total,
        SUM(CASE
                WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget
            END) AS budget_comission,
        SUM(CASE
                WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget
            END) AS budget
    FROM
        datalake_gsheets_clean.mexico_costs_targets
    GROUP BY 1, 2, 3, 4
),
supply_actual_costs AS (
    SELECT
        DATE_TRUNC('month', dt_week_started) AS month_start,
        city_group,
        CASE 
            WHEN planning_mkt_level3 IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_origin,
        CASE 
            WHEN planning_mkt_level3 = 'Landing page - PWA' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Organic traffic' THEN 'Organic'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_channel,
        SUM(budget) AS actual_cost,
        SUM(CASE
                WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget
            END) AS actual_cost_comission,
        SUM(CASE 
                WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget
            END) AS cost
    FROM
        datalake_gsheets_clean.mexico_supply_costs_financial_and_actual
    GROUP BY 1, 2, 3, 4
),
daily_published_listings AS (
    SELECT
        f.sk_house_listing,
        f.status_history,
        d.date,
        d.month_end,
        ROW_NUMBER() OVER(PARTITION BY f.sk_house_listing, d.date ORDER BY f.ts_status_start DESC) AS order_status
    FROM
        dw_public.fact_house_listing_status AS f
    JOIN
        dw_public.dim_date AS d
            ON d.date = LAST_DAY(ts_status_start)
    WHERE
        d.date >= DATE('2022-06-01')
        AND f.status_history = 'publicado'
        AND SUBSTR(CAST(sk_house_listing AS STRING), 10, 12) <> '000' -- Consider only listings that already started publication
),
daily_published_listings_adjusted AS (
    SELECT
        fhs.sk_house_listing,
        fhs.date,
        fhs.month_end,
        fhs.order_status,
        fhs.status_history,
        fhl.sk_region,
        dr.city_group
    FROM
        daily_published_listings AS fhs
    LEFT JOIN
        dw_public.fact_house_listings AS fhl
            ON fhs.sk_house_listing = fhl.sk_house_listing
    LEFT JOIN
        mexico_regions AS dr
            ON fhl.sk_region = dr.sk_region
    WHERE
        fhs.order_status = 1
        AND dr.city_group IS NOT NULL
        AND dr.id_country = 2
        AND fhs.date = fhs.month_end
),
ongoing_listings AS (
    SELECT
        month_end,
        city_group,
        COUNT(DISTINCT sk_house_listing) AS ongoing_listings
    FROM
        daily_published_listings_adjusted
    GROUP BY 1, 2
),
leads AS (
    SELECT 
        fhlf.sk_lead,
        fhlf.sk_lead_date,
        fhlf.sk_region,
        dl.country_code,
        dr.city_group,
        fhlf.mkt_origin,
        fhlf.mkt_channel,
        dl.ub_page_name,
        dl.criado_em
    FROM 
        mexico_listing_flows AS fhlf
    LEFT JOIN 
        dw_public.dim_lead AS dl
            ON fhlf.sk_lead = dl.sk_lead
    LEFT JOIN 
        mexico_regions AS dr
            ON fhlf.sk_region = dr.sk_region
),
leads_rules AS (
    SELECT
        DATE_TRUNC('month', TO_DATE(CAST(sk_lead_date AS STRING),'yyyymmdd')) AS month_start,
        COALESCE(city_group,'Not mapped') AS city_group,
        mkt_origin AS supply_mkt_origin,
        CASE
            WHEN mkt_origin = 'Owner PWA' THEN mkt_channel
            WHEN mkt_origin != 'Owner PWA' THEN mkt_origin
        END AS supply_mkt_origin_detailed,
        COUNT(sk_lead_date) AS leads,
        COUNT(CASE
                WHEN ub_page_name = 'Registrar Lead' THEN sk_lead_date
            END) AS leads_ub_human_crawlers,
        COUNT(CASE
                WHEN ub_page_name = 'Leads NAVENT' THEN sk_lead_date
            END) AS leads_ub_i24,
        COUNT(CASE
                WHEN ub_page_name = 'Landing Owner Mexico' THEN sk_lead_date
            END) AS leads_ub_owner_mex
    FROM 
        leads
    GROUP BY 1, 2, 3, 4
)
SELECT 
    dim.year AS base_year,
    dim.month_start,
    dim.country_name,
    dim.city_group,
    sf.supply_mkt_origin, 
    sf.supply_mkt_origin_detailed,
    CASE
        WHEN sf.supply_mkt_origin = 'Owner PWA' AND sf.supply_mkt_origin_detailed = 'Organic' THEN 'Organic Traffic'
        WHEN sf.supply_mkt_origin = 'Owner PWA' AND sf.supply_mkt_origin_detailed = 'Paid' THEN 'Landing Page - PWA'
        WHEN sf.supply_mkt_origin = 'Indica Aí - General' THEN 'Refiere y Gana'
        WHEN sf.supply_mkt_origin = 'CIQ' THEN 'CIB'
        WHEN sf.supply_mkt_origin = 'LP Navent' THEN 'I24'
        ELSE 'Other'
    END AS mexico_channel,
    sf.leads,
    lr.leads_ub_i24,
    lr.leads_ub_human_crawlers,
    lr.leads_ub_owner_mex,
    sf.prospects,
    sf.qualifieds,
    sf.opportunities,
    sf.first_listings,
    CAST(sft.prospects AS FLOAT) AS prospects_targets,
    CAST(sft.qualifieds AS FLOAT) AS qualifieds_targets,
    CAST(sft.opportunities AS FLOAT) AS opportunities_targets,
    CAST(sft.first_listings AS FLOAT) AS first_listings_targets,
    CAST(sf.qualifieds/CAST(NULLIF(sf.prospects, 0) AS FLOAT) AS FLOAT) AS p2q,
    CAST(sf.first_listings/CAST(NULLIF(sf.qualifieds, 0) AS FLOAT) AS FLOAT) AS q2fl,
    ol.ongoing_listings,
    CAST(sct.budget_total AS FLOAT) AS budget_total_target,
    CAST(sct.budget_comission AS FLOAT) AS budget_comission_target,
    CAST(sct.budget AS FLOAT) AS budget_target,
    CAST(sac.actual_cost AS FLOAT) AS actual_cost,
    CAST(sac.actual_cost_comission AS FLOAT) AS actual_cost_comission,
    CAST(sac.cost AS FLOAT) AS cost,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM 
    dimensions AS dim
LEFT JOIN 
    supply_funnel AS sf
        ON dim.month_start = sf.month_start 
        AND dim.city_group = sf.city_group
LEFT JOIN 
    supply_funnel_targets AS sft
        ON dim.month_start = sft.month_start 
        AND dim.city_group = sft.city_group 
        AND sf.supply_mkt_origin = sft.supply_origin
        AND sf.supply_mkt_origin_detailed = sft.supply_channel
LEFT JOIN
    leads_rules AS lr
        ON dim.month_start = lr.month_start 
        AND dim.city_group = lr.city_group 
        AND sf.supply_mkt_origin = lr.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = lr.supply_mkt_origin_detailed
LEFT JOIN
   supply_costs_targets AS sct
        ON sct.month_start = dim.month_start
        AND sct.city_group = dim.city_group
        AND sf.supply_mkt_origin = sct.supply_origin
        AND sf.supply_mkt_origin_detailed = sct.supply_channel
LEFT JOIN
    supply_actual_costs AS sac
        ON sac.month_start = dim.month_start
        AND sac.city_group = dim.city_group
        AND sf.supply_mkt_origin = sac.supply_origin
        AND sf.supply_mkt_origin_detailed = sac.supply_channel
LEFT JOIN
    ongoing_listings AS ol
        ON dim.month_end = ol.month_end
        AND dim.city_group = ol.city_group