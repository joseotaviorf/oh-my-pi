WITH supply_cohort_funnel_base AS (
    SELECT 
        DATE_TRUNC('week', TO_DATE(CAST(sk_lead_date AS STRING),'yyyymmdd')) AS week_start,
        DATE_TRUNC('month', TO_DATE(CAST(sk_lead_date AS STRING),'yyyymmdd')) AS month_start,
        country_name,
        city_group,
        supply_mkt_origin, 
        supply_mkt_origin_detailed,
        CASE 
            WHEN mexico_channel = 'CIQ' THEN 'CIB'
            WHEN mexico_channel = 'Owner PWA' AND supply_mkt_origin_detailed = 'Organic'  THEN 'Landing page - PWA'
            WHEN mexico_channel = 'Owner PWA' AND supply_mkt_origin_detailed = 'Paid' THEN 'Organic Traffic'
            ELSE mexico_channel
        END AS mexico_channel,
        COUNT(sk_lead_date) AS leads,
        COUNT(CASE
                WHEN sk_prospect_date > 0 THEN sk_prospect_date
            END
        ) AS prospects_cohort,
        COUNT(CASE
                WHEN sk_qualified_date > 0 THEN sk_qualified_date
            END
        ) AS qualifieds_cohort,
        COUNT(CASE
                WHEN sk_opportunity_date > 0 THEN sk_opportunity_date
            END
        ) AS opportunities_cohort,
        COUNT(CASE
                WHEN sk_first_listing_date > 0 THEN sk_first_listing_date
            END
        ) AS first_listings_cohort
    FROM
        reverse_navent_bigquery.mexico_supply_funnel
    GROUP BY 1, 2, 3, 4, 5, 6, 7 
)
SELECT 
    country_name,
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
    opportunities_cohort/CAST(NULLIF(qualifieds_cohort, 0) AS REAL) AS q20_cohort,
    first_listings_cohort/CAST(NULLIF(opportunities_cohort, 0) AS REAL) AS O2fl_cohort,
    DATE(week_start) AS dt_lead_week_started,
    DATE(month_start) AS dt_lead_month_started,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    supply_cohort_funnel_base