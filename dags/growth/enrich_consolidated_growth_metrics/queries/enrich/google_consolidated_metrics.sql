WITH campaign_reports AS (
        SELECT
            DISTINCT campaign_name,
            id_campaign,
            ad_group_name,
            report_type,
            device,
            ad_network_type
        FROM
            datalake_google_ads_clean.ads_performance
        WHERE
            dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        UNION ALL
        SELECT
            DISTINCT campaign_name,
            id_campaign,
            ad_group_name,
            report_type,
            device,
            ad_network_type
        FROM
            datalake_google_ads_clean.keywords_performance
        WHERE
            dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
            AND id_keyword NOT BETWEEN 3000000 AND 3000006 -- these campaigns should be extracted from ADS report
        UNION ALL
        SELECT
            DISTINCT campaign_name,
            id_campaign,
            NULL AS ad_group_name,
            report_type,
            device,
            ad_network_type
        FROM
            datalake_google_ads_clean.campaigns_performance
        WHERE
            dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        UNION ALL
        SELECT
            DISTINCT campaign_name,
            id_campaign,
            ad_group_name,
            report_type,
            device,
            ad_network_type
        FROM
            datalake_google_ads_clean.videos_performance
        WHERE
            dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    ),
    report_type_mapping AS (
        SELECT
            campaign_name,
            id_campaign,
            ad_group_name,
            device,
            ad_network_type,
            CASE
                WHEN (
                    LOWER(campaign_name) LIKE '%discovery%' OR
                    LOWER(campaign_name) LIKE '%smart%'
                )
                THEN 'AD_PERFORMANCE_REPORT'
                WHEN ANY(report_type = 'VIDEO_PERFORMANCE_REPORT')
                THEN 'VIDEO_PERFORMANCE_REPORT'
                WHEN ANY(report_type = 'KEYWORDS_PERFORMANCE_REPORT')
                THEN 'KEYWORDS_PERFORMANCE_REPORT'
                WHEN ANY(report_type = 'AD_PERFORMANCE_REPORT')
                THEN 'AD_PERFORMANCE_REPORT'
                WHEN EVERY(EVERY(report_type = 'CAMPAIGN_PERFORMANCE_REPORT')) OVER (PARTITION BY campaign_name, id_campaign)
                THEN 'CAMPAIGN_PERFORMANCE_REPORT'
        END AS report_type
    FROM
        campaign_reports
    GROUP BY 1, 2, 3, 4, 5
),

-- Joining selected report types to reports

keywords_metrics AS (
    SELECT
        INT(REPLACE(gkpr.dt_loaded, '-', '')) AS id_date,
        gkpr.campaign_name,
        gkpr.account_snake_case AS account_name,
        gkpr.country_code,
        gkpr.report_type,
        NULL AS ad_type,
        criteria || '_' || LOWER(LEFT(match_type, 1)) AS utm_term,
        NULL AS utm_content,
        gkpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN gkpr.device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN gkpr.device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(CASE
            WHEN gkpr.device NOT IN ('MOBILE', 'TABLET',  'DESKTOP') THEN cost/1000000
            ELSE 0
        END) AS other_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks,
        SUM(conversions) AS conversions
    FROM
        datalake_google_ads_clean.keywords_performance gkpr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gkpr.campaign_name
            AND rtm.ad_group_name = gkpr.ad_group_name
            AND rtm.report_type = 'KEYWORDS_PERFORMANCE_REPORT'
            AND rtm.device = gkpr.device
            AND rtm.ad_network_type = gkpr.ad_network_type
    WHERE
        dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        1,2,3,4,5,6,7,8,9
),

-- TEMPORARY CTE UNTIL THIS GSHEETS IS UDPATED
ad_type_flags AS (
    SELECT
        flag,
        report_type,
        CASE
            WHEN ad_type = 'Responsive search ad' THEN 'RESPONSIVE_SEARCH_AD'
            WHEN ad_type = 'Expanded dynamic search ad' THEN 'EXPANDED_DYNAMIC_SEARCH_AD'
            WHEN ad_type = 'Responsive display ad' THEN 'RESPONSIVE_DISPLAY_AD'
            WHEN ad_type = 'Gmail ad' THEN 'GMAIL_AD'
            WHEN ad_type = 'Call only ad' THEN 'CALL_AD'
            WHEN ad_type = 'Image ad' THEN 'IMAGE_AD'
            ELSE ad_type
        END AS ad_type
    FROM datalake_gsheets_clean.marketing_costs_google_ad_type_flags
),

ads_metrics AS (
    SELECT
        INT(REPLACE(gapr.dt_loaded, '-', '')) AS id_date,
        gapr.campaign_name,
        gapr.account_snake_case AS account_name,
        gapr.country_code,
        gapr.report_type,
        COALESCE(ad_types.flag, 'other') AS ad_type,
        STRING(gapr.ad_group_name) AS utm_term,
        STRING(id_ad) AS utm_content,
        gapr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN gapr.device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN gapr.device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(CASE
            WHEN gapr.device NOT IN ('MOBILE', 'TABLET',  'DESKTOP') THEN cost/1000000
            ELSE 0
        END) AS other_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks, 
        SUM(conversions) AS conversions
    FROM
        datalake_google_ads_clean.ads_performance gapr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gapr.campaign_name
            AND rtm.ad_group_name = gapr.ad_group_name
            AND rtm.report_type = 'AD_PERFORMANCE_REPORT'
            AND rtm.device = gapr.device
            AND rtm.ad_network_type = gapr.ad_network_type
    LEFT JOIN
        ad_type_flags ad_types
            ON ad_types.ad_type = gapr.ad_type
    WHERE
        dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        1,2,3,4,5,6,7,8,9
),

campaigns_metrics AS (
    SELECT
        INT(REPLACE(gcpr.dt_loaded, '-', '')) AS id_date,
        gcpr.campaign_name,
        gcpr.account_snake_case AS account_name,
        gcpr.country_code,
        gcpr.report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        gcpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN gcpr.device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN gcpr.device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(CASE
            WHEN gcpr.device NOT IN ('MOBILE', 'TABLET',  'DESKTOP') THEN cost/1000000
            ELSE 0
        END) AS other_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks, 
        SUM(conversions) AS conversions
    FROM
        datalake_google_ads_clean.campaigns_performance gcpr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gcpr.campaign_name
            AND rtm.report_type = 'CAMPAIGN_PERFORMANCE_REPORT'
            AND rtm.device = gcpr.device
            AND rtm.ad_network_type = gcpr.ad_network_type
    WHERE
        dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        1,2,3,4,5,6,7,8,9
),

videos_metrics AS (
    SELECT
        INT(REPLACE(gvpr.dt_loaded, '-', '')) AS id_date,
        gvpr.campaign_name,
        gvpr.account_snake_case AS account_name,
        gvpr.country_code,
        gvpr.report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        gvpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN gvpr.device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN gvpr.device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(CASE
            WHEN gvpr.device NOT IN ('MOBILE', 'TABLET',  'DESKTOP') THEN cost/1000000
            ELSE 0
        END) AS other_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks, 
        SUM(conversions) AS conversions
    FROM
        datalake_google_ads_clean.videos_performance gvpr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gvpr.campaign_name
            AND rtm.ad_group_name = gvpr.ad_group_name
            AND rtm.report_type = 'VIDEO_PERFORMANCE_REPORT'
            AND rtm.device = gvpr.device
            AND rtm.ad_network_type = gvpr.ad_network_type
    WHERE
        dt_loaded BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        1,2,3,4,5,6,7,8,9
)

SELECT * FROM keywords_metrics
UNION ALL
SELECT * FROM ads_metrics
UNION ALL
SELECT * FROM campaigns_metrics
UNION ALL
SELECT * FROM videos_metrics
