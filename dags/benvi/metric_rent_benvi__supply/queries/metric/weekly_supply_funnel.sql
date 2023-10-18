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
coincident_funnel AS (
    SELECT
        city_group,
        supply_mkt_origin,
        supply_mkt_origin_detailed,
        mexico_channel,
        SUM(leads) AS leads,
        SUM(prospects) AS prospects,
        SUM(qualifieds) AS qualifieds,
        SUM(available_qualifieds) AS available_qualifieds,
        SUM(opportunities) AS opportunities,
        SUM(first_listings) AS first_listings,
        dt_week_started
    FROM
        datalake_mexico_rent_supply.coincident_funnel
    GROUP BY 1, 2, 3, 4, 11
),
cohort_funnel AS (
    SELECT
        city_group,
        supply_mkt_origin,
        supply_mkt_origin_detailed,
        mexico_channel,
        SUM(prospects_cohort) AS prospects_cohort,
        SUM(qualifieds_cohort) AS qualifieds_cohort,
        SUM(available_qualifieds_cohort) AS available_qualifieds_cohort,
        SUM(opportunities_cohort) AS opportunities_cohort,
        SUM(first_listings_cohort) AS first_listings_cohort,
        SUM(l2p_cohort) AS l2p_cohort,
        SUM(p2q_cohort) AS p2q_cohort,
        SUM(q2aq_cohort) AS q2aq_cohort,
        SUM(q2o_cohort) AS q2o_cohort,
        SUM(aq2o_cohort) AS aq2o_cohort,
        SUM(o2fl_cohort) AS o2fl_cohort,
        dt_lead_week_started
    FROM
        datalake_mexico_rent_supply.cohort_funnel
    GROUP BY 1, 2, 3, 4, 16
)
SELECT
    COALESCE(dim.country_code, 'Undefined') AS country_code,
    COALESCE(dim.city_group, 'Undefined') AS city_group,
    cf.supply_mkt_origin,
    cf.supply_mkt_origin_detailed,
    cf.mexico_channel AS mexico_channel,
    cf.leads,
    -- Coincident actual volumes
    cf.prospects,
    cf.qualifieds,
    cf.available_qualifieds,
    cf.opportunities,
    cf.first_listings,
    -- Cohort actual volumes
    cfl.prospects_cohort,
    cfl.qualifieds_cohort,
    cfl.available_qualifieds_cohort,
    cfl.opportunities_cohort,
    cfl.first_listings_cohort,
    -- Coincident "conversions"
    ROUND(CAST(cf.prospects/NULLIF(cf.leads, 0) AS FLOAT), 2) AS l2p_coincident,
    ROUND(CAST(cf.qualifieds/NULLIF(cf.prospects, 0) AS FLOAT), 2) AS p2q_coincident,
    ROUND(CAST(cf.available_qualifieds/NULLIF(cf.qualifieds, 0) AS FLOAT), 2) AS q2aq_coincident,
    ROUND(CAST(cf.opportunities/NULLIF(cf.qualifieds, 0) AS FLOAT), 2) AS q2o_coincident,
    ROUND(CAST(cf.opportunities/NULLIF(cf.available_qualifieds, 0) AS FLOAT), 2) AS aq2o_coincident,
    ROUND(CAST(cf.first_listings/NULLIF(cf.opportunities, 0) AS FLOAT), 2) AS o2fl_coincident,
    ROUND(CAST(cf.first_listings/NULLIF(cf.qualifieds, 0) AS FLOAT), 2) AS q2fl_coincident,
    ROUND(CAST(cf.first_listings/NULLIF(cf.prospects, 0) AS FLOAT), 2) AS p2fl_coincident,
    -- Cohort conversions
    cfl.l2p_cohort,
    cfl.p2q_cohort,
    cfl.q2aq_cohort,
    cfl.q2o_cohort,
    cfl.aq2o_cohort,
    cfl.o2fl_cohort,
    DATE(dim.dt_week_started) AS dt_week_started
FROM
    mexico_regions AS dim
LEFT JOIN
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
