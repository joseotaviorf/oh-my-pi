WITH mexico_regions AS (
    SELECT DISTINCT
        dt_week_started,
        country_code,
        COALESCE(city_group, 'Not Mapped') AS city_group
    FROM
        datalake_region.city_groups_per_periods
    WHERE
        country_code = 'MX'
        AND dt_month_started >= DATE('2022-06-01')
),
supply_funnel_targets AS (
    SELECT
        COALESCE(city_group, 'Not Mapped') AS city_group,
        CASE 
            WHEN supply_origin IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN supply_origin = 'Indica Ai - General' THEN 'Indica Aí - General'
            WHEN supply_origin = 'Refiere y Gana' THEN 'Indica Aí - General'
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
            WHEN supply_origin = 'Owner PWA' THEN supply_channel
            WHEN supply_origin = 'I24' THEN 'LP Navent'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS supply_mkt_origin_detailed,
        CASE 
            WHEN supply_origin = 'Owner PWA' AND supply_channel = 'Paid' THEN 'Landing Page - PWA'
            WHEN supply_origin = 'Owner PWA' AND supply_channel = 'Organic' THEN 'Organic Traffic - PWA'
            WHEN supply_origin LIKE '%Indica%' THEN 'Refiere y Gana'
            WHEN supply_origin = 'CIQ' THEN 'CIB'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS mexico_channel,
        SUM(CAST(NULLIF(top_of_funnel,'') AS REAL)) AS leads,
        SUM(CAST(NULLIF(prospects,'') AS REAL)) AS prospects,
        SUM(CAST(NULLIF(qualifieds,'') AS REAL)) AS qualifieds,
        SUM(CAST(NULLIF(opportunities,'') AS REAL)) AS opportunities,
        SUM(CAST(NULLIF(first_listings,'') AS REAL)) AS first_listings,
        DATE(DATE_TRUNC('week', DATE(dt_target))) AS dt_week_started
    FROM 
        datalake_gsheets_clean.mexico_supply_targets_2022
    WHERE
        DATE_TRUNC('week', DATE(dt_target)) <= DATE_ADD(CURRENT_DATE, -1) 
        AND supply_channel NOT IN ('Crawlers classifieds', 'Price Calculator')    
    GROUP BY 1, 2, 3, 4, 10
),
supply_budget_targets AS (
    SELECT 
        COALESCE(city_group, 'Not Mapped') AS city_group,
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
        SUM(CASE WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget END) AS budget_comission,
        SUM(CASE WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget END) AS budget,
        dt_week AS dt_week_started
    FROM
        datalake_gsheets_clean.mexico_costs_targets
    WHERE
        planning_mkt_level3 <> 'Price Calculator'
    GROUP BY 1, 2, 3, 7
),
supply_actual_costs AS (
    SELECT
        COALESCE(city_group, 'Not Mapped') AS city_group,
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
        SUM(CASE WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget END) AS actual_cost_comission,
        SUM(CASE WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget END) AS cost,
        dt_week_started
    FROM
        datalake_gsheets_clean.mexico_supply_costs_financial_and_actual
    WHERE
        planning_mkt_level3 <> 'Price Calculator'
    GROUP BY 1, 2, 3, 7
),
market_place AS (
    -- We are still using the datamart as a source since it's the actual solution for churn metric
    SELECT 
        COALESCE(dr.city_group, 'Not Mapped') AS city_group,
        COUNT(DISTINCT CASE WHEN rmf.status_short = 'Ongoing Listing' THEN rmf.sk_house_listing END) AS ongoing_listings,
        COUNT(DISTINCT CASE WHEN rmf.status_short = 'Other' AND rmf.status_last_week_short IN ('Ongoing Listing', 'Advanced Negociation', 'New Listing') THEN rmf.sk_house_listing END) - 
            COUNT(DISTINCT CASE WHEN rmf.status_last_week_short = 'Other' AND rmf.status_short = 'Ongoing Listing' THEN rmf.sk_house_listing END) AS net_churn,
        rmf.week_start AS dt_week_started
    FROM 
        dw_datamarts_growth_cross.rental_marketplace_flows AS rmf
    JOIN 
        datalake_region.region AS dr
            ON rmf.sk_region = dr.id 
    WHERE
        dr.country_code = 'MX'
        AND rmf.week_start >= DATE('2022-06-01')
    GROUP BY 1, 4
),
coincident_funnel AS (
    SELECT
        city_group,
        supply_mkt_origin,
        supply_mkt_origin_detailed,
        mexico_channel,
        SUM(leads) AS leads,
        SUM(prospects) AS prospects,
        SUM(qualifieds) AS qualifieds,
        SUM(opportunities) AS opportunities,
        SUM(first_listings) AS first_listings,
        dt_week_started
    FROM
        datalake_mexico_rent_supply_funnel.coincident_funnel
    GROUP BY 1, 2, 3, 4, 10
),
cohort_funnel AS (
    SELECT
        city_group,
        supply_mkt_origin,
        supply_mkt_origin_detailed,
        mexico_channel,
        SUM(prospects_cohort) AS prospects_cohort,
        SUM(qualifieds_cohort) AS qualifieds_cohort,
        SUM(opportunities_cohort) AS opportunities_cohort,
        SUM(first_listings_cohort) AS first_listings_cohort,
        SUM(l2p_cohort) AS l2p_cohort,
        SUM(p2q_cohort) AS p2q_cohort,
        SUM(q2o_cohort) AS q2o_cohort,
        SUM(o2fl_cohort) AS o2fl_cohort,
        dt_lead_week_started
    FROM
        datalake_mexico_rent_supply_funnel.cohort_funnel 
    GROUP BY 1, 2, 3, 4, 13
)
SELECT 
    COALESCE(dim.country_code, 'Other') AS country_code,
    COALESCE(dim.city_group, 'Not Mapped') AS city_group,
    cf.supply_mkt_origin, 
    cf.supply_mkt_origin_detailed,
    COALESCE(cf.mexico_channel, sft.mexico_channel) AS mexico_channel,     
    cf.leads,
    -- Coincident actual volumes
    cf.prospects,
    cf.qualifieds,
    cf.opportunities,
    cf.first_listings,
    -- Cohort actual volumes
    cfl.prospects_cohort,
    cfl.qualifieds_cohort,
    cfl.opportunities_cohort,
    cfl.first_listings_cohort,
    -- Coincident "conversions"
    CAST(cf.prospects/CAST(NULLIF(cf.leads,0) AS REAL) AS FLOAT) AS l2p_coincident,
    CAST(cf.qualifieds/CAST(NULLIF(cf.prospects,0) AS REAL) AS FLOAT) AS p2q_coincident,
    CAST(cf.opportunities/CAST(NULLIF(cf.qualifieds,0) AS REAL) AS FLOAT) AS q2o_coincident,
    CAST(cf.first_listings/CAST(NULLIF(cf.opportunities,0) AS REAL) AS FLOAT) AS o2fl_coincident,
    -- Cohort conversions
    CAST(cfl.l2p_cohort AS FLOAT) AS l2p_cohort,
    CAST(cfl.p2q_cohort AS FLOAT) AS p2q_cohort,
    CAST(cfl.q2o_cohort AS FLOAT) AS q2o_cohort,
    CAST(cfl.o2fl_cohort AS FLOAT) AS o2fl_cohort,
    -- Actual volume targets
    CAST(sft.leads AS FLOAT) AS leads_targets,
    CAST(sft.prospects AS FLOAT) AS prospects_targets,
    CAST(sft.qualifieds AS FLOAT) AS qualifieds_targets,
    CAST(sft.opportunities AS FLOAT) AS opportunities_targets,
    CAST(sft.first_listings AS FLOAT) AS first_listings_targets,
    -- Actual costs
    CAST(sac.actual_cost AS FLOAT) AS actual_cost,
    CAST(sac.actual_cost_comission AS FLOAT) AS actual_cost_comission,
    CAST(sac.cost AS FLOAT) AS cost,
    -- Targets cost 
    CAST(sbt.budget_total AS FLOAT) AS budget_total_target,
    CAST(sbt.budget_comission AS FLOAT) AS budget_comission_target,
    CAST(sbt.budget AS FLOAT) AS budget_target,
    -- Listings
    mp.ongoing_listings,
    mp.net_churn,
    DATE(COALESCE(dim.dt_week_started, sft.dt_week_started)) AS dt_week_started
FROM
    mexico_regions AS dim
JOIN
    coincident_funnel AS cf
        ON dim.dt_week_started = cf.dt_week_started 
        AND dim.city_group = cf.city_group
LEFT JOIN
    cohort_funnel AS cfl
        ON dim.dt_week_started = cfl.dt_lead_week_started 
        AND dim.city_group = cfl.city_group 
        AND cf.supply_mkt_origin = cfl.supply_mkt_origin
        AND cf.supply_mkt_origin_detailed = cfl.supply_mkt_origin_detailed
        AND cf.mexico_channel = cfl.mexico_channel
FULL OUTER JOIN
    supply_funnel_targets AS sft
        ON dim.dt_week_started = sft.dt_week_started 
        AND dim.city_group = sft.city_group 
        AND cf.supply_mkt_origin = sft.supply_mkt_origin
        AND cf.supply_mkt_origin_detailed = sft.supply_mkt_origin_detailed 
        AND cf.mexico_channel = sft.mexico_channel
LEFT JOIN
    supply_budget_targets AS sbt
        ON dim.dt_week_started = sbt.dt_week_started 
        AND dim.city_group = sbt.city_group 
        AND cf.supply_mkt_origin = sbt.supply_mkt_origin
        AND cf.supply_mkt_origin_detailed = sbt.supply_mkt_origin_detailed
LEFT JOIN
    supply_actual_costs AS sac
        ON dim.dt_week_started = sac.dt_week_started 
        AND dim.city_group = sac.city_group 
        AND cf.supply_mkt_origin = sac.supply_mkt_origin
        AND cf.supply_mkt_origin_detailed = sac.supply_mkt_origin_detailed
LEFT JOIN
    market_place AS mp
        ON dim.dt_week_started = mp.dt_week_started 
        AND dim.city_group = mp.city_group