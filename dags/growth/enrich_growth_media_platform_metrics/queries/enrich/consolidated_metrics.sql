WITH all_metrics AS (
    --  Facebook Metrics
    SELECT 
        *
    FROM 
        datalake_growth_media_platform.facebook_metrics
    WHERE 
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    UNION ALL
    -- Criteo Metrics
    SELECT 
        *
    FROM
        datalake_growth_media_platform.criteo_metrics
    WHERE 
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    -- Google Ads Metrics
    UNION ALL
    SELECT 
        *
    FROM
        datalake_growth_media_platform.google_metrics
    WHERE 
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    -- Trovit Metrics
    UNION ALL
    SELECT
        *
    FROM
        datalake_growth_media_platform.trovit_metrics
    WHERE
        dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
),
translation_dictionary AS (
    SELECT  
        account_name,
        campaign_name AS utm_campaign,
        origin,
        campaign_name_convention
    FROM 
        datalake_gsheets_clean.cost_taxonomy_translation_dictionary
    GROUP BY ALL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY account_name, campaign_name, origin ORDER BY campaign_name_convention) = 1
)

SELECT 
    am.id_account,
    am.id_campaign,
    am.id_adset,
    am.id_ad,
    am.account_name,
    am.origin,
    am.report_type,
    am.utm_campaign,
    am.utm_term,
    am.utm_content,
    am.country_code,
    am.state,
    am.city,
    am.clicks,
    am.conversions,
    am.impressions,
    am.total_cost,
    CASE
        WHEN 
        td.campaign_name_convention IS NOT NULL 
        THEN 'sufix_from_dictionary'
        WHEN 
        NULLIF(CONCAT_WS('.', SLICE(SPLIT(am.utm_campaign, '[.]'), 2, 7)), '') IS NOT NULL 
        THEN 'sufix_from_campaign'
        ELSE 
        'not_mapped'
    END AS type_flow_media_setup,
    COALESCE(
        td.campaign_name_convention, -- sufix_from_dictionary,
        NULLIF(CONCAT_WS('.', SLICE(SPLIT(am.utm_campaign, '[.]'), 2, 7)), '') -- sufix_from_campaign
    ) AS name_convention_suffix,
    am.dt_cost,
    am.year,
    am.month,
    am.day
FROM 
    all_metrics AS am
LEFT JOIN 
    translation_dictionary AS td
        ON (am.origin = td.origin)
        AND (am.account_name = td.account_name)
        AND (am.utm_campaign = td.utm_campaign) 
WHERE 
    (am.clicks > 0)
    OR (am.impressions > 0)
    OR (am.total_cost > 0)
    -- (OR am.conversions > 0) -- TO-DO: enable after adjust the logic