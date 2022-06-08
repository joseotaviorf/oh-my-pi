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
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_marketing_metrics.google_consolidated_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- CRITEO
    UNION ALL
    SELECT
        id_date,
        'criteo' AS origin,
        campaign_name,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_marketing_metrics.criteo_consolidated_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- RTB
    UNION ALL
    SELECT
        id_date,
        'rtb' AS origin,
        campaign_name,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_marketing_metrics.rtb_consolidated_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- MITULA
    UNION ALL
    SELECT
        id_date,
        'mitula' AS origin,
        campaign_name,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        0 AS impressions,
        clicks
    FROM
        datalake_consolidated_marketing_metrics.mitula_consolidated_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- TROVIT
    UNION ALL
    SELECT
        id_date,
        'trovit' AS origin,
        campaign_name,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        0 AS impressions,
        clicks
    FROM
        datalake_consolidated_marketing_metrics.trovit_consolidated_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    -- FACEBOOK
    UNION ALL
    SELECT
        id_date,
        'facebook' AS origin,
        campaign_name,
        account_name,
        NULL AS report_type,
        NULL AS ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        desktop_cost,
        mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_marketing_metrics.facebook_consolidated_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
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
    COALESCE(ch.city_group, sr.city_group, dr.city_group, 'Not Mapped') AS city_group,
    cs.report_type,
    cs.ad_type,
    cs.utm_campaign,
    cs.utm_term,
    cs.utm_content,
    cs.desktop_cost * COALESCE(sr.share, 1) AS desktop_cost,
    cs.mobile_cost * COALESCE(sr.share, 1) AS mobile_cost,
    cs.other_cost * COALESCE(sr.share, 1) AS other_cost,
    cs.total_cost * COALESCE(sr.share, 1) AS total_cost,
    cs.impressions * COALESCE(sr.share, 1) AS impressions,
    cs.clicks * COALESCE(sr.share, 1) AS clicks
FROM
    consolidated_sources cs
LEFT JOIN
    datalake_marketing_costs_sharing_rules.old_sharing_rules sr
        ON SPLIT(cs.campaign_name, '[.]')[0] = sr.id_rule
        AND cs.id_date = sr.id_date
LEFT JOIN
    datalake_consolidated_marketing_costs.city_group_old_campaigns_historic ch
        ON cs.campaign_name = ch.campaign_name
LEFT JOIN
    datalake_region.region dr
        ON SPLIT(cs.campaign_name, '[.]')[0] = dr.id
