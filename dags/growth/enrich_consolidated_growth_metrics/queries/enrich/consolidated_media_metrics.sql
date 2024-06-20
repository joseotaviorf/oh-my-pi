WITH consolidated_sources AS (
    -- GOOGLE
    SELECT
        id_date,
        'google' AS origin,
        NULL AS business_context,
        campaign_name,
        account_name,
        'BR' AS country_code,
        report_type,
        ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        NULL AS city_group,
        desktop_cost,
        mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_growth_metrics.google_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- CRITEO
    UNION ALL
    SELECT
        id_date,
        'criteo' AS origin,
        NULL AS business_context,
        campaign_name,
        account_name,
        country_code,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        NULL AS city_group,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_growth_metrics.criteo_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- RTB
    UNION ALL
    SELECT
        id_date,
        'rtb' AS origin,
        NULL AS business_context,
        campaign_name,
        account_name,
        country_code,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        NULL AS city_group,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_growth_metrics.rtb_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- MITULA
    UNION ALL
    SELECT
        id_date,
        'mitula' AS origin,
        NULL AS business_context,
        campaign_name,
        account_name,
        country_code,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        NULL AS city_group,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        0 AS impressions,
        clicks
    FROM
        datalake_consolidated_growth_metrics.mitula_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- TROVIT
    UNION ALL
    SELECT
        id_date,
        'trovit' AS origin,
        NULL AS business_context,
        campaign_name,
        account_name,
        country_code,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        utm_campaign,
        NULL AS city_group,
        desktop_cost,
        mobile_cost,
        0.0 AS other_cost,
        total_cost,
        0 AS impressions,
        clicks
    FROM
        datalake_consolidated_growth_metrics.trovit_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- FACEBOOK
    UNION ALL
    SELECT
        id_date,
        'facebook' AS origin,
        NULL AS business_context,
        campaign_name,
        account_name,
        'BR' AS country_code,
        NULL AS report_type,
        NULL AS ad_type,
        utm_term,
        utm_content,
        utm_campaign,
        NULL AS city_group,
        desktop_cost,
        mobile_cost,
        other_cost,
        total_cost,
        impressions,
        clicks
    FROM
        datalake_consolidated_growth_metrics.facebook_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
    -- BRAZE
    UNION ALL
    SELECT
        id_date,
        'braze' AS origin,
        NULL AS business_context,
        campaign_name,
        account_name,
        'BR' AS country_code,
        NULL AS report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        NULL AS utm_campaign,
        city_group,
        0.0 AS desktop_cost,
        0.0 AS mobile_cost,
        0.0 AS other_cost,
        cost AS total_cost,
        0 AS impressions,
        0 AS clicks
    FROM
        datalake_consolidated_growth_metrics.braze_consolidated_metrics
    WHERE
        id_date BETWEEN INT(REPLACE(DATE('{load_start_date}'), '-', '')) AND INT(REPLACE(DATE('{load_end_date}'), '-', ''))
        AND id_date >= 20220912
)

SELECT DISTINCT
    cs.id_date,
    cs.origin,
    COALESCE(sr_utm.business_context, sr.business_context) AS business_context,
    cs.account_name,
    cs.campaign_name,
    cs.country_code,
    COALESCE(ctd.campaign_name_convention, ARRAY_JOIN(SLICE(SPLIT(cs.campaign_name,'[.]'), 2, 7), '.')) AS campaign_name_convention_media_setup,
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
    CASE
        WHEN cs.origin = 'braze' THEN cs.city_group
        ELSE COALESCE(ch.city_group, sr_utm.city_group, sr.city_group, dr.city_group, 'Not Mapped')
    END AS city_group,
    cs.report_type,
    cs.ad_type,
    cs.utm_campaign,
    cs.utm_term,
    cs.utm_content,
    cs.desktop_cost * COALESCE(sr_utm.share, sr.share, 1) AS desktop_cost,
    cs.mobile_cost * COALESCE(sr_utm.share, sr.share, 1) AS mobile_cost,
    cs.other_cost * COALESCE(sr_utm.share, sr.share, 1) AS other_cost,
    cs.total_cost * COALESCE(sr_utm.share, sr.share, 1) AS total_cost,
    cs.impressions * COALESCE(sr_utm.share, sr.share, 1) AS impressions,
    cs.clicks * COALESCE(sr_utm.share, sr.share, 1) AS clicks
FROM
    consolidated_sources cs
LEFT JOIN
    datalake_growth_costs_sharing_rules.sharing_rules sr
ON
    SPLIT(cs.campaign_name, '[.]')[0] = sr.id_rule
    AND cs.id_date = sr.id_date
    AND sr.utm_campaign_modified IS NULL
LEFT JOIN
    datalake_growth_costs_sharing_rules.sharing_rules sr_utm
ON
    SPLIT(cs.campaign_name, '[.]')[0] = sr_utm.id_rule
    AND cs.id_date = sr_utm.id_date
    AND SUBSTRING(cs.utm_campaign, INSTR(cs.utm_campaign, '.') + 1) = sr_utm.utm_campaign_modified
    AND sr_utm.utm_campaign_modified IS NOT NULL
LEFT JOIN
    datalake_consolidated_marketing_costs.city_group_old_campaigns_historic ch
ON
    cs.campaign_name = ch.campaign_name
LEFT JOIN
    datalake_region.region dr
ON
    SPLIT(cs.campaign_name, '[.]')[0] = dr.id
LEFT JOIN
    datalake_gsheets_clean.cost_taxonomy_translation_dictionary AS ctd
ON
  cs.account_name = ctd.account_name
  AND COALESCE(cs.campaign_name,"") = COALESCE(ctd.campaign_name,"")
  AND COALESCE(cs.report_type,"") = COALESCE(ctd.report_type,"")
  AND COALESCE(cs.ad_type,"") = COALESCE(ctd.ad_type,"")
  AND COALESCE(cs.origin,"") = COALESCE(ctd.origin,"")
WHERE
    cs.id_date IS NOT NULL
