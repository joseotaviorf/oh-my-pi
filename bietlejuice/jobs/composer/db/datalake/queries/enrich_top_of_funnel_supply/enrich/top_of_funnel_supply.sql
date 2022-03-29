WITH
    events AS (
        SELECT
            DATE(ts_event) AS dt_event,
            DATE(DATE_TRUNC('WEEK', ts_event)) AS week_start_event,
            MONTH(ts_event) AS month,
            EXTRACT(QUARTER FROM ts_event) AS quarter_event,
            CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING) AS utm_campaign,
            COUNT(distinct id_amplitude) AS unique_user
        FROM
            datalake_amplitude_clean.events
        WHERE
            event_type IN ('landing_page_viewed', 'price_suggestion_page_viewed', 'price_suggestion_sale_page_viewed') 
            AND id_app = 183047
            AND CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS STRING) in ('google', 'facebook')
            AND CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS STRING) in ('cpc', 'display', 'performance_max')
            AND LOWER(CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING)) NOT LIKE '%branded%' 
            AND LOWER(CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING)) NOT LIKE '%demand%'
            AND year = {year}
            AND month = {month}
            AND day = {day}
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
    txn.campaign_name,
    txn.account_name,
    txn.utm_campaign,
    txn.utm_term,
    txn.utm_content,
    txn.city_group,
    rgn.tier,
    txn.campaign_origin_acquisition,
    txn.mkt_category,
    txn.mkt_flow,
    txn.mkt_completion,
    txn.mkt_origin,
    txn.mkt_medium,
    txn.mkt_source,
    txn.mkt_channel,
    txn.mkt_platform,
    txn.funnel_side,
    txn.flow_type,
    evt.dt_event,
    evt.week_start_event,
    evt.quarter_event,
    IF(evt.quarter_event < 3, 1, 2) AS half_year_event,
    SUM(evt.unique_user) AS traffic,
    YEAR(evt.dt_event) as year,
    evt.month,
    DAY(evt.dt_event) as day
FROM events evt 
LEFT JOIN taxonomy txn
    ON txn.order_l = 1
        AND txn.utm_campaign = evt.utm_campaign
LEFT JOIN regions rgn
    ON txn.city_group = rgn.city_group
WHERE
    txn.utm_campaign IS NOT NULL
GROUP BY 
    1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,24,25,26
