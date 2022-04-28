WITH campaign_reports AS (
    SELECT DISTINCT
        campaign_name,
        id_campaign,
        ad_group_name,
        report_type
    FROM
        datalake_casa_mineira_google_ads_clean.ads_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')

    UNION ALL

    SELECT DISTINCT
        campaign_name,
        id_campaign,
        ad_group_name,
        report_type
    FROM
        datalake_casa_mineira_google_ads_clean.keywords_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')

    UNION ALL

    SELECT DISTINCT
        campaign_name,
        id_campaign,
        NULL AS ad_group_name,
        report_type
    FROM
        datalake_casa_mineira_google_ads_clean.campaigns_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')

    UNION ALL

    SELECT DISTINCT
        campaign_name,
        id_campaign,
        ad_group_name,
        report_type
    FROM
        datalake_casa_mineira_google_ads_clean.videos_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
),


report_type_mapping AS (
    SELECT
        campaign_name,
        id_campaign,
        ad_group_name,
        CASE
            WHEN (LOWER(campaign_name) LIKE '%discovery%'
               OR LOWER(campaign_name) LIKE '%smart%') 
                THEN 'AD_PERFORMANCE_REPORT'
            WHEN ANY(report_type='VIDEO_PERFORMANCE_REPORT')
                THEN 'VIDEO_PERFORMANCE_REPORT'
            WHEN ANY(report_type='KEYWORDS_PERFORMANCE_REPORT')
                THEN 'KEYWORDS_PERFORMANCE_REPORT'
            WHEN ANY(report_type='AD_PERFORMANCE_REPORT')
                THEN 'AD_PERFORMANCE_REPORT'
            WHEN EVERY(EVERY(report_type='CAMPAIGN_PERFORMANCE_REPORT')) OVER (PARTITION BY campaign_name, id_campaign)
                THEN 'CAMPAIGN_PERFORMANCE_REPORT'
        END AS report_type
    FROM
        campaign_reports
    GROUP BY 1, 2, 3
),

-- Joining selected report types to reports

keywords_metrics AS (
    SELECT
        INT(REPLACE(gkpr.dt_loaded, '-', '')) AS id_date,
        gkpr.campaign_name,
        gkpr.account_descriptive_name AS account_name,
        gkpr.report_type,
        NULL AS ad_type,
        criteria || '_' || LOWER(LEFT(match_type, 1)) AS utm_term,
        NULL AS utm_content,
        gkpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks
    FROM
        datalake_casa_mineira_google_ads_clean.keywords_performance_report gkpr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gkpr.campaign_name
            AND rtm.ad_group_name = gkpr.ad_group_name
            AND rtm.report_type = 'KEYWORDS_PERFORMANCE_REPORT'
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
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
        gapr.account_descriptive_name AS account_name,
        gapr.report_type,
        COALESCE(ad_types.flag, 'other') AS ad_type,
        STRING(gapr.ad_group_name) AS utm_term,
        STRING(id_ad) AS utm_content,
        gapr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks
    FROM
        datalake_casa_mineira_google_ads_clean.ads_performance_report gapr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gapr.campaign_name
            AND rtm.ad_group_name = gapr.ad_group_name
            AND rtm.report_type = 'AD_PERFORMANCE_REPORT'
    LEFT JOIN
        ad_type_flags ad_types
            ON ad_types.ad_type = gapr.ad_type
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
),

campaigns_metrics AS (
    SELECT
        INT(REPLACE(gcpr.dt_loaded, '-', '')) AS id_date,
        gcpr.campaign_name,
        gcpr.account_descriptive_name AS account_name,
        gcpr.report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        gcpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks
    FROM
        datalake_casa_mineira_google_ads_clean.campaigns_performance_report gcpr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gcpr.campaign_name
            AND rtm.report_type = 'CAMPAIGN_PERFORMANCE_REPORT'
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
),

videos_metrics AS (
    SELECT
        INT(REPLACE(gvpr.dt_loaded, '-', '')) AS id_date,
        gvpr.campaign_name,
        gvpr.account_descriptive_name AS account_name,
        gvpr.report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        gvpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'DESKTOP' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('MOBILE', 'TABLET') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks
    FROM
        datalake_casa_mineira_google_ads_clean.videos_performance_report gvpr
    JOIN
        report_type_mapping rtm
            ON rtm.campaign_name = gvpr.campaign_name
            AND rtm.ad_group_name = gvpr.ad_group_name
            AND rtm.report_type = 'VIDEO_PERFORMANCE_REPORT'
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
)

SELECT * FROM keywords_metrics
UNION ALL
SELECT * FROM ads_metrics
UNION ALL
SELECT * FROM campaigns_metrics
UNION ALL
SELECT * FROM videos_metrics
