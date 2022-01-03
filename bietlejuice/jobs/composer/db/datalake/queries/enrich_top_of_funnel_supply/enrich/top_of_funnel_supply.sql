WITH
    events AS (
        SELECT
            DATE(ts_event) AS date,
            DATE(DATE_TRUNC('WEEK', ts_event)) AS week,
            MONTH(ts_event) AS month,
            EXTRACT(QUARTER FROM ts_event) AS quarter,
            GET_JSON_OBJECT(event_properties, '$.uri') as uri,
            CASE 
                WHEN event_type = 'landing_page_viewed'
                    THEN 'OwnerPWA'
                WHEN event_type = 'price_suggestion_page_viewed'
                    THEN 'Price Calculator'
                WHEN event_type = 'price_suggestion_sale_page_viewed'
                    THEN 'Price Calculator - Sale'
                WHEN CAST(GET_JSON_OBJECT(user_properties, '$.uri') AS STRING) like '%mkt.quintoandar.com.br/ebook-altaigpm%'
                    THEN 'New Channels'
                WHEN CAST(GET_JSON_OBJECT(user_properties, '$.uri') AS STRING) like '%mkt.quintoandar.com.br/ebook-top10itens%'
                    THEN 'New Channels'
                ELSE NULL
            END AS origin,
            CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS STRING) AS utm_source,
            CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS STRING) AS utm_medium,
            CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING) AS utm_campaign,
            SPLIT(CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING), '\\\\.')[0] AS sk_region,
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
            1,2,3,4,5,6,7,8,9,10
    ),
    old_campaigns AS (
        SELECT
            DISTINCT
                campaign_name,
                city_group
        FROM
            datalake_consolidated_marketing_costs.city_group_old_campaigns_historic
        UNION
        SELECT
            DISTINCT
                campaign_name,
                city_group
        FROM
            datalake_gsheets_clean.marketing_costs_campaign_city
    ),
    regions AS (
        SELECT
            sk_region,
            city_group,
            tier
        FROM (
            SELECT
                id AS sk_region,
                city_group,
                tier,
                ROW_NUMBER() OVER (PARTITION BY city_group ORDER BY id DESC) AS order_l
            FROM
                datalake_region.region
            GROUP BY
                1, 2, 3
            ) AS filter
        WHERE
            order_l = 1
    ),
    taxonomy AS (
        SELECT
            DISTINCT
                campaign_name,
                mkt_origin,
                mkt_channel,
                mkt_medium,
                mkt_source
        FROM (
            SELECT
                id_date,
                campaign_name,
                mkt_origin,
                mkt_channel,
                mkt_medium,
                mkt_source,
                ROW_NUMBER() OVER (PARTITION BY campaign_name ORDER BY id_date DESC) AS order_l
            FROM
                datalake_marketing_costs.daily_costs
            WHERE
                mkt_origin IN ('Owner PWA', 'Price Calculator', 'Owner PWA - Sale', 'Price Calculator - Sale', 'New Channels')
            GROUP BY
                1, 2, 3, 4, 5, 6
        )
        WHERE
            order_l = 1
    ),
    total AS (
        SELECT 
            cte.date,
            cte.week,
            cte.month,
            cte.quarter,
            IF(cte.quarter < 3, 1, 2) AS half_year,
            COALESCE(b.city_group, a.city_group) AS city_group,
            COALESCE(b.tier, a.tier) AS tier,
            t.mkt_origin,
            t.mkt_medium,
            t.mkt_source,
            t.mkt_channel,
            SUM(unique_user) as traffic
        FROM events cte 
        LEFT JOIN old_campaigns hc
            ON cte.utm_campaign = hc.campaign_name
        LEFT JOIN datalake_region.region a
            ON a.id = cte.sk_region
        LEFT JOIN regions b 
            ON b.city_group = hc.city_group
        LEFT JOIN taxonomy t
            ON TRIM(t.campaign_name) = TRIM(cte.utm_campaign)
        GROUP BY 
            1,2,3,4,5,6,7,8,9,10,11
    )
SELECT 
    total.date AS dt_event,
    total.week AS week_start_event,
    total.month AS month_event,
    total.quarter AS quarter_event,
    total.half_year AS half_year_event,
    total.city_group,
    total.tier,
    mkt_origin,
    mkt_medium,
    mkt_source,
    mkt_channel,
    ta.traffic AS traffic_target,
    total.traffic,
    year(total.date) as year,
    month(total.date) as month,
    day(total.date) as day
FROM 
    total
LEFT JOIN datalake_gsheets_clean.tof_supply_targets ta
    ON ta.dt_target = total.date
        AND ta.city_group = total.city_group
        AND ta.supply_origin = total.mkt_origin
        AND ta.supply_channel = total.mkt_channel
        AND ta.supply_medium = total.mkt_medium
        AND ta.supply_source  = total.mkt_source
WHERE 
    total.city_group IS NOT NULL