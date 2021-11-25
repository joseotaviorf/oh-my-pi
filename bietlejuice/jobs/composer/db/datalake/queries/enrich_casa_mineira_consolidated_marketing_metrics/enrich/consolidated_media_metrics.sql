-- Union of medias
WITH medias_consolidated AS (
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
        datalake_casa_mineira_consolidated_marketing_metrics.google_consolidated_metrics
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
        datalake_casa_mineira_consolidated_marketing_metrics.criteo_consolidated_metrics
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
        datalake_casa_mineira_consolidated_marketing_metrics.rtb_consolidated_metrics
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
        datalake_casa_mineira_consolidated_marketing_metrics.mitula_consolidated_metrics
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
        datalake_casa_mineira_consolidated_marketing_metrics.trovit_consolidated_metrics
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
        datalake_casa_mineira_consolidated_marketing_metrics.facebook_consolidated_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
)

SELECT 
    mc.id_date,
    origin,
    account_name,
    mc.campaign_name,
    COALESCE(sr.city_group, dr.city_group, 'Not Mapped') AS city_group,
    report_type,
    ad_type,
    utm_campaign,
    utm_term,
    utm_content,
    desktop_cost * COALESCE(sr.share, 1) AS desktop_cost,
    mobile_cost * COALESCE(sr.share, 1) AS mobile_cost,
    other_cost * COALESCE(sr.share, 1) AS other_cost,
    total_cost * COALESCE(sr.share, 1) AS total_cost,
    impressions * COALESCE(sr.share, 1) AS impressions,
    clicks * COALESCE(sr.share, 1) AS clicks
FROM 
    medias_consolidated mc
LEFT JOIN 
    datalake_marketing_costs_sharing_rules.old_sharing_rules sr
        ON SPLIT(mc.campaign_name, '\\\\.')[0] = sr.id_rule
        AND mc.id_date = sr.id_date 
LEFT JOIN 
    datalake_region.region dr
        ON SPLIT(mc.campaign_name, '\\\\.')[0] = dr.id
