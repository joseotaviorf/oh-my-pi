WITH page_view_events AS (
    SELECT DISTINCT
        DATE(ts_event) AS dt_event,
        up_utm_campaign AS utm_campaign,
        id_amplitude
    FROM
        datalake_amplitude_clean.183047_price_suggestion_page_viewed_events
    WHERE
        DATE(ts_event) = DATE('{year}-{month}-{day}')
        AND up_utm_source IN ('google', 'facebook')
        AND up_utm_medium IN ('cpc', 'display', 'performance_max')
        AND LOWER(up_utm_campaign) NOT LIKE '%branded%'
        AND LOWER(up_utm_campaign) NOT LIKE '%demand%'
    UNION ALL
    SELECT DISTINCT
        DATE(ts_event) AS dt_event,
        up_utm_campaign AS utm_campaign,
        id_amplitude
    FROM
        datalake_amplitude_clean.183047_price_suggestion_sale_page_viewed_events
    WHERE
        DATE(ts_event) = DATE('{year}-{month}-{day}')
        AND up_utm_source IN ('google', 'facebook')
        AND up_utm_medium IN ('cpc', 'display', 'performance_max')
        AND LOWER(up_utm_campaign) NOT LIKE '%branded%'
        AND LOWER(up_utm_campaign) NOT LIKE '%demand%'
    UNION ALL
    SELECT DISTINCT
        DATE(ts_event) AS dt_event,
        up_utm_campaign AS utm_campaign,
        id_amplitude
    FROM
        datalake_amplitude_clean.183047_landing_page_viewed_events
    WHERE
        DATE(ts_event) = DATE('{year}-{month}-{day}')
        AND up_utm_source IN ('google', 'facebook')
        AND up_utm_medium IN ('cpc', 'display', 'performance_max')
        AND LOWER(up_utm_campaign) NOT LIKE '%branded%'
        AND LOWER(up_utm_campaign) NOT LIKE '%demand%'
),
page_view_unique_users AS (
    SELECT
        dt_event,
        utm_campaign,
        COUNT(DISTINCT id_amplitude) AS unique_users
    FROM
        page_view_events
    GROUP BY
        1,2
),
taxonomy AS (
    SELECT
        cmm.id_date,
        cmm.utm_campaign,
        cmm.utm_term,
        cmm.utm_content,
        cmm.city_group,
        rgn.tier,
        txn.mkt_origin,
        txn.mkt_channel,
        txn.mkt_medium,
        txn.mkt_source,
        ROW_NUMBER() OVER (PARTITION BY cmm.utm_campaign ORDER BY id_date DESC) AS campaign_date_order
    FROM
        datalake_consolidated_marketing_metrics.consolidated_media_metrics cmm
    INNER JOIN
        datalake_gsheets_clean.marketing_cost_taxonomy AS txn
            ON COALESCE(cmm.account_name, '') = COALESCE(txn.account_name, '')
            AND COALESCE(cmm.report_type, '') = COALESCE(txn.report_type, '')
            AND COALESCE(cmm.ad_type, 'other') = COALESCE(txn.ad_type, 'other')
            AND cmm.origin = txn.origin
            AND cmm.campaign_origin_acquisition = txn.campaign_origin_acquisition
    LEFT JOIN
        datalake_region.region rgn
            ON cmm.city_group = rgn.city_group
    WHERE
        txn.mkt_origin IN (
            'Owner PWA',
            'Price Calculator',
            'Owner PWA - Sale',
            'Price Calculator - Sale',
            'New Channels'
        )
        AND LOWER(SPLIT(cmm.campaign_name, '[.]')[0]) <> 'zebra'
    GROUP BY
        1,2,3,4,5,6,7,8,9,10
)
SELECT
    txn.utm_campaign,
    txn.utm_term,
    txn.utm_content,
    txn.city_group,
    txn.tier,
    txn.mkt_origin,
    txn.mkt_channel,
    txn.mkt_medium,
    txn.mkt_source,
    pve.dt_event,
    SUM(pve.unique_users) AS traffic,
    YEAR(pve.dt_event) AS year,
    MONTH(pve.dt_event) AS month,
    DAY(pve.dt_event) AS day
FROM
    page_view_unique_users pve
INNER JOIN
    taxonomy txn
        ON txn.utm_campaign = pve.utm_campaign
        AND txn.campaign_date_order = 1
GROUP BY
    1,2,3,4,5,6,7,8,9,10
