WITH dimension_period AS (
    SELECT DISTINCT
        year, 
        week_start 
    FROM 
        dw_public.dim_date
    WHERE
        date BETWEEN DATE('2022-06-01') AND DATE_ADD(CURRENT_DATE, -1) 
),
dimension_region AS (
    SELECT DISTINCT
        country_name,
        COALESCE(city_group, 'Not mapped') AS city_group
    FROM 
        dw_public.dim_region
    WHERE 
        id_country = 2
),
dimensions AS (
    SELECT *
    FROM 
        dimension_period
    CROSS JOIN 
        dimension_region
),
supply_funnel_targets AS (
    SELECT
        DATE_TRUNC('week', DATE(dt_target)) AS week_start,
        city_group,
        CASE 
            WHEN supply_origin IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN supply_origin = 'Indica Ai - General' THEN 'Indica Aí - General'
            WHEN supply_origin = 'Refiere y Gana' THEN 'Indica Aí - General'
            WHEN supply_origin = 'CIB' THEN 'CIQ'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS supply_mkt_origin,
        CASE 
            WHEN supply_origin = 'Organic traffic' THEN 'Organic'
            WHEN supply_origin = 'Landing page - PWA' AND supply_channel like '%Paid%' THEN 'Paid' 
            WHEN supply_origin = 'Indica Ai - General' THEN 'Indica Aí - General'
            WHEN supply_origin = 'Refiere y Gana' THEN 'Indica Aí - General'
            WHEN supply_origin = 'CIB' THEN 'CIQ'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            ELSE supply_origin
        END AS supply_mkt_origin_detailed,
        CASE 
            WHEN supply_origin = 'Owner PWA' AND supply_channel = 'Paid' THEN 'Landing page - PWA'
            WHEN supply_origin = 'Owner PWA' AND supply_channel = 'Organic' THEN 'Organic Traffic'
            WHEN supply_origin LIKE '%Indica%' THEN 'Refiere y Gana'
            WHEN supply_origin = 'CIQ' THEN 'CIB'
            WHEN supply_origin LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN supply_origin = 'I24' THEN 'Imuebles 24'
            ELSE supply_origin
        END AS mexico_channel,
        SUM(CAST(NULLIF(top_of_funnel,'') AS REAL)) AS leads,
        SUM(CAST(NULLIF(prospects,'') AS REAL)) AS prospects,
        SUM(CAST(NULLIF(qualifieds,'') AS REAL)) AS qualifieds,
        SUM(CAST(NULLIF(opportunities,'') AS REAL)) AS opportunities,
        SUM(CAST(NULLIF(first_listings,'') AS REAL)) AS first_listings
    FROM 
        datalake_gsheets_clean.mexico_supply_targets_2022
    WHERE
        DATE_TRUNC('week', DATE(dt_target)) <= DATE_ADD(CURRENT_DATE, -1)     
    GROUP BY 1, 2, 3, 4, 5
),
supply_budget_targets AS (
    SELECT 
        dt_week AS week_start, 
        city_group,
        CASE 
            WHEN planning_mkt_level3 IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin,
        CASE 
            WHEN planning_mkt_level3 = 'Landing page - PWA' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Organic traffic' THEN 'Organic'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin_detailed,
        SUM(budget) AS budget_total,
        SUM(CASE WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget END) AS budget_comission,
        SUM(CASE WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget END) AS budget
    FROM
        datalake_gsheets_clean.mexico_costs_targets
    GROUP BY 1, 2, 3, 4 
),
supply_actual_costs AS (
    SELECT
        dt_week_started,
        city_group,
        CASE 
            WHEN planning_mkt_level3 IN ('Landing page - PWA', 'Organic traffic') THEN 'Owner PWA'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin,
        CASE 
            WHEN planning_mkt_level3 = 'Landing page - PWA' THEN 'Paid'
            WHEN planning_mkt_level3 = 'Organic traffic' THEN 'Organic'
            WHEN planning_mkt_level3 LIKE '%Refiere y Gana%' THEN 'Indica Aí - General'
            WHEN planning_mkt_level3 LIKE '%CIB%' THEN 'CIQ'
            WHEN planning_mkt_level3 LIKE '%Human crawlers%' THEN 'Human Crawlers'
            WHEN planning_mkt_level3 LIKE '%I24%' THEN 'i24'
            ELSE planning_mkt_level3 
        END AS supply_mkt_origin_detailed,
        SUM(budget) AS actual_cost,
        SUM(CASE WHEN UPPER(planning_mkt_level3) LIKE '%COMISION%' OR UPPER(planning_mkt_level3) LIKE '%COMISIÓN%' THEN budget END) AS actual_cost_comission,
        SUM(CASE WHEN UPPER(planning_mkt_level3) NOT LIKE '%COMISION%' AND UPPER(planning_mkt_level3) NOT LIKE '%COMISIÓN%' THEN budget END) AS cost
    FROM
        datalake_gsheets_clean.mexico_supply_costs_financial_and_actual
    GROUP BY 1, 2, 3, 4
),
market_place AS (
    SELECT 
        rmf.week_start,
        dr.city_group,
        COUNT(DISTINCT CASE WHEN rmf.status_short = 'Ongoing Listing' THEN rmf.sk_house_listing END) AS ongoing_listings,
        COUNT(DISTINCT CASE WHEN rmf.status_short = 'Other' AND rmf.status_last_week_short IN ('Ongoing Listing', 'Advanced Negociation', 'New Listing') THEN rmf.sk_house_listing END) - 
            COUNT(DISTINCT CASE WHEN rmf.status_last_week_short = 'Other' AND rmf.status_short = 'Ongoing Listing' THEN rmf.sk_house_listing END) AS net_churn
    FROM 
        dw_datamarts_growth_cross.rental_marketplace_flows AS rmf
    JOIN 
        dw_public.dim_region AS dr
            ON rmf.sk_region = dr.sk_region 
    WHERE
        dr.country_name = 'Mexico'
    GROUP BY 1, 2
),
mexico_cohort_base_table AS (
    SELECT
        city_group,
        supply_mkt_origin,
        supply_mkt_origin_detailed,
        mexico_channel,
        prospects_cohort,
        qualifieds_cohort,
        opportunities_cohort,
        first_listings_cohort,
        l2p_cohort,
        p2q_cohort,
        q2o_cohort,
        o2fl_cohort,
        dt_lead_week_started
    FROM
        reverse_navent_bigquery.mexico_supply_funnel_cohort
    WHERE
        year = YEAR(CURRENT_DATE)
        AND month = MONTH(CURRENT_DATE)
        AND day = DAY(CURRENT_DATE)
),
mexico_coincident_base_table AS (
    SELECT
        city_group,
        supply_mkt_origin,
        supply_mkt_origin_detailed,
        mexico_channel,
        leads,
        prospects,
        qualifieds,
        opportunities,
        first_listings,
        dt_week_started
    FROM
        reverse_navent_bigquery.mexico_supply_funnel_coincident
    WHERE
        year = YEAR(CURRENT_DATE)
        AND month = MONTH(CURRENT_DATE)
        AND day = DAY(CURRENT_DATE)
)
SELECT 
    dim.year AS base_year,
    DATE(COALESCE(dim.week_start, sft.week_start)) AS week_start,
    dim.country_name,
    dim.city_group,
    sf.supply_mkt_origin, 
    sf.supply_mkt_origin_detailed,
    COALESCE(sf.mexico_channel,sft.mexico_channel) AS mexico_channel,     
    sf.leads,
    -- Coincident actual volumes
    sf.prospects,
    sf.qualifieds,
    sf.opportunities,
    sf.first_listings,
    -- Cohort actual volumes
    scf.prospects_cohort,
    scf.qualifieds_cohort,
    scf.opportunities_cohort,
    scf.first_listings_cohort,
    -- Coincident "conversions"
    CAST(sf.prospects/CAST(NULLIF(sf.leads,0) AS REAL) AS FLOAT) AS l2p_coincident,
    CAST(sf.qualifieds/CAST(NULLIF(sf.prospects,0) AS REAL) AS FLOAT) AS p2q_coincident,
    CAST(sf.opportunities/CAST(NULLIF(sf.qualifieds,0) AS REAL) AS FLOAT) AS q2o_coincident,
    CAST(sf.first_listings/CAST(NULLIF(sf.opportunities,0) AS REAL) AS FLOAT) AS o2fl_coincident,
    -- Cohort conversions
    CAST(scf.l2p_cohort AS FLOAT) AS l2p_cohort,
    CAST(scf.p2q_cohort AS FLOAT) AS p2q_cohort,
    CAST(scf.q2o_cohort AS FLOAT) AS q2o_cohort,
    CAST(scf.o2fl_cohort AS FLOAT) AS o2fl_cohort,
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
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    dimensions AS dim
JOIN
    mexico_coincident_base_table AS sf
        ON dim.week_start = sf.dt_week_started 
        AND dim.city_group = sf.city_group
LEFT JOIN
    mexico_cohort_base_table AS scf
        ON dim.week_start = scf.dt_lead_week_started 
        AND dim.city_group = scf.city_group 
        AND sf.supply_mkt_origin = scf.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = scf.supply_mkt_origin_detailed
        AND sf.mexico_channel = scf.mexico_channel
FULL OUTER JOIN
    supply_funnel_targets AS sft
        ON dim.week_start = sft.week_start 
        AND dim.city_group = sft.city_group 
        AND sf.supply_mkt_origin = sft.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = sft.supply_mkt_origin_detailed 
        AND sf.mexico_channel = sft.mexico_channel
LEFT JOIN
    supply_budget_targets AS sbt
        ON dim.week_start = sbt.week_start 
        AND dim.city_group = sbt.city_group 
        AND sf.supply_mkt_origin = sbt.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = sbt.supply_mkt_origin_detailed
LEFT JOIN
    supply_actual_costs AS sac
        ON dim.week_start = sac.dt_week_started 
        AND dim.city_group = sac.city_group 
        AND sf.supply_mkt_origin = sac.supply_mkt_origin
        AND sf.supply_mkt_origin_detailed = sac.supply_mkt_origin_detailed
LEFT JOIN
    market_place AS mp
        ON dim.week_start = mp.week_start 
        AND dim.city_group = mp.city_group