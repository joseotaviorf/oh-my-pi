WITH
    events AS (
        SELECT
            DATE(ts_event) AS date,
            DATE(DATE_TRUNC('WEEK', ts_event)) AS week,
            MONTH(ts_event) AS month,
            EXTRACT(QUARTER FROM ts_event) AS quarter,
            CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING) AS utm_campaign,
            COUNT(distinct id_amplitude) AS unique_user
        FROM
            datalake_amplitude_clean.events
        WHERE
            event_type IN ('landing_page_viewed', 'price_suggestion_page_viewed', 'price_suggestion_sale_page_viewed') 
            AND id_app = 183047
            AND DATE(ts_event) = DATE('{year}-{month}-{day}')
            AND CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS STRING) in ('google', 'facebook')
            AND CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS STRING) in ('cpc', 'display', 'performance_max')
            AND LOWER(CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING)) NOT LIKE '%branded%' 
            AND LOWER(CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING)) NOT LIKE '%demand%'
        GROUP BY 
            1,2,3,4,5
    ),
    regions AS (
            SELECT
                DISTINCT
                    city_group,
                    tier
            FROM
                datalake_region.region
    ),
    taxonomy AS (
        SELECT
            id_date, 
            account_name, 
            utm_campaign, 
            utm_term, 
            utm_content, 
            city_group, 
            campaign_origin_acquisition, 
            mkt_category,
            mkt_flow,
            mkt_completion,
            campaign_name, 
            mkt_origin, 
            mkt_channel, 
            mkt_medium, 
            mkt_source, 
            mkt_platform, 
            funnel_side, 
            flow_type, 
            ROW_NUMBER() OVER (PARTITION BY utm_campaign ORDER BY id_date DESC) AS order_l
        FROM
            datalake_marketing_costs.daily_costs
        WHERE
            mkt_origin IN ('Owner PWA', 'Price Calculator', 'Owner PWA - Sale', 'Price Calculator - Sale', 'New Channels')
        GROUP BY
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18
    )
SELECT
    t.campaign_name,
    t.account_name,
    t.utm_campaign,
    t.utm_term,
    t.utm_content,
    t.city_group,
    r.tier,
    t.campaign_origin_acquisition,
    t.mkt_category,
    t.mkt_flow,
    t.mkt_completion,
    t.mkt_origin,
    t.mkt_medium,
    t.mkt_source,
    t.mkt_channel,
    t.mkt_platform,
    t.funnel_side,
    t.flow_type,
    cte.date AS dt_event,
    cte.week AS week_start_event,
    cte.quarter AS quarter_event,
    IF(cte.quarter < 3, 1, 2) AS half_year_event,
    SUM(cte.unique_user) AS traffic,
    year(cte.date) as year,
    cte.month AS month,
    day(cte.date) as day
FROM events cte 
LEFT JOIN taxonomy t
    ON t.order_l = 1
        AND t.utm_campaign = cte.utm_campaign
LEFT JOIN regions r
    ON t.city_group = r.city_group
WHERE
    t.utm_campaign IS NOT NULL
GROUP BY 
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,24,25,26
