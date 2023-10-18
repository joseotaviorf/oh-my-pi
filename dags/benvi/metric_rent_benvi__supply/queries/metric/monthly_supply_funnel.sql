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
)
SELECT
    dim.country_code,
    dim.city_group,
    sf.supply_mkt_origin,
    sf.supply_mkt_origin_detailed,
    sf.mexico_channel,
    sf.leads,
    sf.prospects,
    sf.qualifieds,
    sf.available_qualifieds,
    sf.opportunities,
    sf.first_listings,
    ROUND(CAST(sf.prospects/NULLIF(sf.leads, 0) AS FLOAT), 2) AS l2p_coincident,
    ROUND(CAST(sf.qualifieds/NULLIF(sf.prospects, 0) AS FLOAT), 2) AS p2q_coincident,
    ROUND(CAST(sf.available_qualifieds/NULLIF(sf.qualifieds, 0) AS FLOAT), 2) AS q2aq_coincident,
    ROUND(CAST(sf.opportunities/NULLIF(sf.qualifieds, 0) AS FLOAT), 2) AS q2o_coincident,
    ROUND(CAST(sf.opportunities/NULLIF(sf.available_qualifieds, 0) AS FLOAT), 2) AS aq2o_coincident,
    ROUND(CAST(sf.first_listings/NULLIF(sf.qualifieds, 0) AS FLOAT), 2) AS q2fl_coincident,
    ROUND(CAST(sf.first_listings/NULLIF(sf.opportunities, 0) AS FLOAT), 2) AS o2fl_coincident,
    ROUND(CAST(sf.first_listings/NULLIF(sf.prospects, 0) AS FLOAT), 2) AS p2fl_coincident,
    dim.dt_month_started
FROM
    dimensions AS dim
LEFT JOIN
    supply_funnel AS sf
        ON dim.dt_month_started = sf.dt_month_started
        AND dim.city_group = sf.city_group
