WITH consolidated_sources AS (
    -- GOOGLE
    SELECT
        id_date,
        'google' AS origin,
        campaign_name,
        account_name,
        report_type,
        ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        'MXN' AS currency,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_mexico_consolidated_marketing_metrics.google_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- MITULA
    UNION ALL
    SELECT
        id_date,
        'mitula' AS origin,
        campaign_name,
        account_name,
        CAST(NULL AS STRING) AS report_type,
        CAST(NULL AS STRING) AS ad_type,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS utm_content,
        utm_campaign,
        'USD' AS currency,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        0 AS impressions,
        clicks
    FROM
        datalake_mexico_consolidated_marketing_metrics.mitula_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- TROVIT
    UNION ALL
    SELECT
        id_date,
        'trovit' AS origin,
        campaign_name,
        account_name,
        CAST(NULL AS STRING) AS report_type,
        CAST(NULL AS STRING) AS ad_type,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS utm_content,
        utm_campaign,
        'USD' AS currency,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        0 AS impressions,
        clicks
    FROM
        datalake_mexico_consolidated_marketing_metrics.trovit_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- FACEBOOK
    UNION ALL
    SELECT
        id_date,
        'facebook' AS origin,
        campaign_name,
        account_name,
        CAST(NULL AS STRING) AS report_type,
        CAST(NULL AS STRING) AS ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        'USD' AS currency,
        desktop_cost,
        mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_mexico_consolidated_marketing_metrics.facebook_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
)
SELECT
    cs.id_date,
    cs.origin,
    cs.account_name,
    cs.campaign_name,
    CASE
        WHEN LOWER(cs.campaign_name) LIKE '%calc%'
            THEN 'Calculator'
        WHEN LOWER(cs.campaign_name) LIKE '%newchannel%'
            THEN 'New Channels'
        WHEN LOWER(cs.campaign_name) LIKE '%agents%'
            THEN 'Agents'
        WHEN LOWER(cs.campaign_name) LIKE '%doorman%'
            THEN 'Doorman'
        ELSE 'Other'
    END AS campaign_origin_acquisition,
    COALESCE(dr.city_group, 'Not Mapped') AS city_group,
    cs.report_type,
    cs.ad_type,
    cs.utm_campaign,
    cs.utm_term,
    cs.utm_content,
    cs.currency,
    cs.desktop_cost,
    cs.mobile_cost,
    cs.other_cost,
    cs.total_cost,
    cs.impressions,
    cs.clicks
FROM
    consolidated_sources AS cs
LEFT JOIN
    datalake_region.region AS dr
        ON SPLIT(cs.campaign_name, '[.]')[0] = dr.id