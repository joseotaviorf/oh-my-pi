WITH supply_cohort_funnel_base AS (
    SELECT
        country_code,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        mexico_channel,
        COUNT(ts_lead) AS leads,
        COUNT(CASE
                WHEN ts_prospect IS NOT NULL THEN ts_prospect
            END
        ) AS prospects_cohort,
        COUNT(CASE
                WHEN ts_qualified IS NOT NULL THEN ts_qualified
            END
        ) AS qualifieds_cohort,
        COUNT(CASE
                WHEN ts_opportunity IS NOT NULL THEN ts_opportunity
            END
        ) AS opportunities_cohort,
        COUNT(CASE
                WHEN ts_first_listing IS NOT NULL THEN ts_first_listing
            END
        ) AS first_listings_cohort,
        DATE_TRUNC('month', ts_lead) AS dt_month_started,
        DATE_TRUNC('week', ts_lead) AS dt_week_started
    FROM
        datalake_mexico_rent_supply_funnel.mexico_rent_listing_flow
    GROUP BY 1, 2, 3, 4, 5, 11, 12
)
SELECT 
    country_code,
    city_group,
    supply_mkt_origin, 
    supply_mkt_origin_detailed,
    mexico_channel,
    leads,
    prospects_cohort,
    qualifieds_cohort,
    opportunities_cohort,
    first_listings_cohort,
    prospects_cohort/CAST(NULLIF(leads, 0) AS REAL) AS l2p_cohort,
    qualifieds_cohort/CAST(NULLIF(prospects_cohort, 0) AS REAL) AS p2q_cohort,
    opportunities_cohort/CAST(NULLIF(qualifieds_cohort, 0) AS REAL) AS q2o_cohort,
    first_listings_cohort/CAST(NULLIF(opportunities_cohort, 0) AS REAL) AS o2fl_cohort,
    dt_week_started AS dt_lead_week_started,
    dt_month_started AS dt_lead_month_started
FROM
    supply_cohort_funnel_base