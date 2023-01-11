WITH dimensions AS (
    SELECT DISTINCT
        country_code,
        COALESCE(city_group, 'Undefined') AS city_group,
        dt_month_started,
        LAST_DAY(dt_month_started) AS dt_month_ended
    FROM
        datalake_region.city_groups_per_periods
    WHERE
        country_code = 'MX'
        AND dt_month_started >= DATE('2022-06-01')
),
supply_funnel AS (
    SELECT 
        COALESCE(city_group, 'Undefined') AS city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        SUM(leads) AS leads,
        SUM(prospects) AS prospects,
        SUM(qualifieds) AS qualifieds,
        SUM(available_qualifieds) AS available_qualifieds,
        SUM(opportunities) AS opportunities,
        SUM(first_listings) AS first_listings,
        dt_month_started,
        LAST_DAY(dt_month_started) AS dt_month_ended
    FROM 
        datalake_mexico_rent_supply.coincident_funnel
    GROUP BY 1, 2, 3, 4, 11, 12
),
supply_funnel_targets AS (
    SELECT
        COALESCE(city_group, 'Undefined') AS city_group,
        CASE 
            WHEN supply_origin IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN supply_origin = 'Refiere y Gana' THEN 'Indica Aí - General'
            WHEN supply_origin LIKE '%Indica Ai%' THEN 'Indica Aí - General'
            WHEN supply_origin = 'CIB' THEN 'CIQ'
            WHEN supply_origin = 'I24' THEN 'LP Navent'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS supply_mkt_origin,
        CASE 
            WHEN supply_origin = 'Organic traffic' THEN 'Organic'
            WHEN supply_origin = 'Landing page - PWA' AND supply_channel LIKE '%Paid%' THEN 'Paid' 
            WHEN supply_origin = 'Indica Ai - General' THEN 'Indica Aí - General'
            WHEN supply_origin = 'Refiere y Gana' THEN 'Indica Aí - General'
            WHEN supply_origin = 'CIB' THEN 'CIQ'
            WHEn supply_origin = 'I24' THEN 'LP Navent'
            WHEN supply_origin = 'Owner PWA' THEN supply_channel
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS supply_mkt_origin_detailed,
        SUM(CAST(NULLIF(top_of_funnel,'') AS REAL)) AS leads_targets,
        SUM(CAST(NULLIF(prospects,'') AS REAL)) AS prospects_targets,
        SUM(CAST(NULLIF(available_qualifieds, '') AS REAL)) AS available_qualifieds_targets,
        SUM(CAST(NULLIF(qualifieds,'') AS REAL)) AS qualifieds_targets,
        SUM(CAST(NULLIF(opportunities,'') AS REAL)) AS opportunities_targets,
        SUM(CAST(NULLIF(first_listings,'') AS REAL)) AS first_listings_targets,
        DATE(DATE_TRUNC('month', DATE(dt_target))) AS dt_month_started
    FROM 
        datalake_gsheets_clean.mexico_supply_targets_2022
    WHERE
        supply_origin NOT IN ('Crawlers classifieds', 'Price Calculator')
    GROUP BY 1, 2, 3, 10
),
supply_costs_targets AS (
    SELECT
        COALESCE(city_group, 'Undefined') AS city_group,
        CASE 
            WHEN planning_mkt_level3 IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'LP Navent'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin,
        CASE 
            WHEN planning_mkt_level3 = 'Landing page - PWA' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Organic traffic' THEN 'Organic'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'LP Navent'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin_detailed,
        SUM(budget) AS budget_total,
        SUM(CASE
                WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget
            END) AS budget_comission,
        SUM(CASE
                WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget
            END) AS budget,
        DATE(DATE_TRUNC('month', dt_week)) AS dt_month_started
    FROM
        datalake_gsheets_clean.mexico_costs_targets
    GROUP BY 1, 2, 3, 7
),
supply_actual_costs AS (
    SELECT
        COALESCE(city_group, 'Undefined') AS city_group,
        CASE 
            WHEN planning_mkt_level3 IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'LP Navent'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin,
        CASE 
            WHEN planning_mkt_level3 = 'Landing page - PWA' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Organic traffic' THEN 'Organic'
            WHEN planning_mkt_level3 = 'I24' THEN 'LP Navent'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin_detailed,
        SUM(budget) AS actual_cost,
        SUM(CASE
                WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget
            END) AS actual_cost_comission,
        SUM(CASE 
                WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget
            END) AS cost,
        DATE(DATE_TRUNC('month', dt_week_started)) AS dt_month_started
    FROM
        datalake_gsheets_clean.mexico_supply_costs_financial_and_actual
    GROUP BY 1, 2, 3, 7
),
house_listings AS (
    SELECT
        hld.id_house_listing,
        COALESCE(rg.city_group, 'Undefined') AS city_group,
        ROW_NUMBER() OVER(PARTITION BY hld.id_house_listing, d.date ORDER BY hld.ts_status_started DESC) AS order_status,
        hld.ts_status_started,
        d.month_end AS dt_month_ended
    FROM
        datalake_rental_historical_follow_up.house_listings_daily_info AS hld
    LEFT JOIN
        datalake_region.region AS rg
            ON rg.id = hld.id_region
    JOIN
        datalake_quintoandar.aux_date AS d
            ON d.date = LAST_DAY(hld.ts_status_started)
    WHERE
        hld.id_country = 2
        AND hld.status_history = 'publicado'
        AND DATE(ts_status_started) >= DATE('2022-06-01')
),
ongoing_listings AS (
    SELECT
        COUNT(id_house_listing) AS ongoing_listings,
        city_group,
        dt_month_ended
    FROM
        house_listings
    WHERE
        order_status = 1
  GROUP BY 2, 3
),
leads_rules AS (
    SELECT
        fhlf.city_group,
        fhlf.supply_mkt_origin,
        fhlf.supply_mkt_origin_detailed,
        COUNT(fhlf.ts_lead) AS leads,
        COUNT(
            CASE
                WHEN dl.unbounce_page_name = 'Registrar Lead' THEN fhlf.ts_lead
            END)
        AS leads_ub_human_crawlers,
        COUNT(
            CASE
                WHEN dl.unbounce_page_name = 'Leads NAVENT' THEN fhlf.ts_lead
            END)
        AS leads_ub_i24,
        COUNT(
            CASE
                WHEN dl.unbounce_page_name = 'Landing Owner Mexico' THEN fhlf.ts_lead
            END)
        AS leads_ub_owner_mx,
        DATE(DATE_TRUNC('month', DATE(fhlf.ts_lead))) AS dt_month_started
    FROM 
        datalake_mexico_rent_supply.listing_flow AS fhlf
    LEFT JOIN 
        datalake_lead.lead AS dl
            ON fhlf.id_lead = dl.id
    GROUP BY 1, 2, 3, 8
)
SELECT 
    dim.country_code,
    dim.city_group,
    sf.supply_mkt_origin, 
    sf.supply_mkt_origin_detailed,
    sf.mexico_channel,
    sf.leads,
    lr.leads_ub_i24,
    lr.leads_ub_human_crawlers,
    lr.leads_ub_owner_mx,
    sf.prospects,
    sf.qualifieds,
    sf.available_qualifieds,
    sf.opportunities,
    sf.first_listings,
    ROUND(sft.leads_targets, 2) AS leads_targets,
    ROUND(sft.prospects_targets, 2) AS prospects_targets,
    ROUND(sft.available_qualifieds_targets, 2) AS available_qualifieds_targets,
    ROUND(sft.qualifieds_targets, 2) AS qualifieds_targets,
    ROUND(sft.opportunities_targets, 2) AS opportunities_targets,
    ROUND(sft.first_listings_targets, 2) AS first_listings_targets,
    ROUND(CAST(sf.prospects/NULLIF(sf.leads, 0) AS FLOAT), 2) AS l2p_coincident,
    ROUND(CAST(sf.qualifieds/NULLIF(sf.prospects, 0) AS FLOAT), 2) AS p2q_coincident,
    ROUND(CAST(sf.available_qualifieds/NULLIF(sf.qualifieds, 0) AS FLOAT), 2) AS q2aq_coincident,
    ROUND(CAST(sf.opportunities/NULLIF(sf.qualifieds, 0) AS FLOAT), 2) AS q2o_coincident,
    ROUND(CAST(sf.opportunities/NULLIF(sf.available_qualifieds, 0) AS FLOAT), 2) AS aq2o_coincident,
    ROUND(CAST(sf.first_listings/NULLIF(sf.qualifieds, 0) AS FLOAT), 2) AS q2fl_coincident,
    ROUND(CAST(sf.first_listings/NULLIF(sf.opportunities, 0) AS FLOAT), 2) AS o2fl_coincident,
    ROUND(CAST(sf.first_listings/NULLIF(sf.prospects, 0) AS FLOAT), 2) AS p2fl_coincident,
    ol.ongoing_listings,
    CAST(sct.budget_total AS FLOAT) AS budget_total_target,
    CAST(sct.budget_comission AS FLOAT) AS budget_comission_target,
    CAST(sct.budget AS FLOAT) AS budget_target,
    CAST(sac.actual_cost AS FLOAT) AS actual_cost,
    CAST(sac.actual_cost_comission AS FLOAT) AS actual_cost_comission,
    CAST(sac.cost AS FLOAT) AS cost,
    dim.dt_month_started
FROM 
    dimensions AS dim
LEFT JOIN 
    supply_funnel AS sf
        ON dim.dt_month_started = sf.dt_month_started 
        AND dim.city_group = sf.city_group
LEFT JOIN 
    supply_funnel_targets AS sft
        ON dim.dt_month_started = sft.dt_month_started 
        AND dim.city_group = sft.city_group 
        AND sf.supply_mkt_origin = sft.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = sft.supply_mkt_origin_detailed
LEFT JOIN
    leads_rules AS lr
        ON dim.dt_month_started = lr.dt_month_started 
        AND dim.city_group = lr.city_group 
        AND sf.supply_mkt_origin = lr.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = lr.supply_mkt_origin_detailed
LEFT JOIN
   supply_costs_targets AS sct
        ON sct.dt_month_started = dim.dt_month_started
        AND sct.city_group = dim.city_group
        AND sf.supply_mkt_origin = sct.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = sct.supply_mkt_origin_detailed
LEFT JOIN
    supply_actual_costs AS sac
        ON sac.dt_month_started = dim.dt_month_started
        AND sac.city_group = dim.city_group
        AND sf.supply_mkt_origin = sac.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = sac.supply_mkt_origin_detailed
LEFT JOIN
    ongoing_listings AS ol
        ON dim.dt_month_ended = ol.dt_month_ended
        AND dim.city_group = ol.city_group