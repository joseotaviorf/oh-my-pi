-- Defining the best report to use
WITH campaing_reports AS (
    SELECT DISTINCT 
        campaign_name,
        id_campaign,
        'ads_performance_report' AS report_type
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')

    UNION ALL

    SELECT DISTINCT 
        campaign_name, 
        id_campaign, 
        'keywords_performance_report' AS report_type 
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')

    UNION ALL

    SELECT DISTINCT 
        campaign_name, 
        id_campaign, 
        'campaigns_performance_report' AS report_type 
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')

    UNION ALL

    SELECT DISTINCT 
        campaign_name, 
        id_campaign, 
        'videos_performance_report' AS report_type 
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
),

pivot_campaign_reports AS (
    SELECT
        campaign_name,
        id_campaign,
        CASE 
            WHEN ARRAY_CONTAINS(COLLECT_LIST(report_type), 'ads_performance_report')
                THEN 'ads_performance_report'
            ELSE NULL
        END AS has_ads_performance_report,
        CASE 
            WHEN ARRAY_CONTAINS(COLLECT_LIST(report_type), 'keywords_performance_report')
                THEN 'keywords_performance_report'
            ELSE NULL
        END AS has_keywords_performance_report,
        CASE 
            WHEN ARRAY_CONTAINS(COLLECT_LIST(report_type), 'campaigns_performance_report')
                THEN 'campaigns_performance_report'
            ELSE NULL
        END AS has_campaigns_performance_report,
        CASE 
            WHEN ARRAY_CONTAINS(COLLECT_LIST(report_type), 'videos_performance_report')
                THEN 'videos_performance_report'
            ELSE NULL
        END AS has_videos_performance_report
    FROM
        campaing_reports
    GROUP BY
      1,2
), 

campaign_main_report_type AS (
    SELECT
        campaign_name,
        id_campaign,
        CASE
            WHEN (
                LOWER(campaign_name) LIKE '%discovery%'
                OR LOWER(campaign_name) LIKE '%smart%'
            ) 
                THEN 'ads_performance_report'
            ELSE 
                COALESCE(
                     has_videos_performance_report,
                     has_keywords_performance_report,
                     has_ads_performance_report,
                     has_campaigns_performance_report
                )
        END AS report_type
    FROM
        pivot_campaign_reports
),

-- Joining selected report types to reports

keywords_costs AS (
    SELECT
        INT(REPLACE(gkpr.dt_loaded, '-', '')) AS id_date,
        gkpr.campaign_name,
        LOWER(
            CASE WHEN SPLIT(gkpr.campaign_name, '\\.')[1] RLIKE '[0-9]+$' THEN
                SPLIT(gkpr.campaign_name, '\\.')[2]
            ELSE
                SPLIT(gkpr.campaign_name, '\\.')[1]
            END
        ) AS campaign_city,
        gkpr.account_descriptive_name AS account_name,
        cmrt.report_type,
        NULL AS ad_type,
        criteria || '_' || LOWER(LEFT(match_type, 1)) AS utm_term,
        NULL AS utm_content,
        gkpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'Computers' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('Mobile devices with full browsers', 'Tablets with full browsers') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost
    FROM
        datalake_google_ads_clean.keywords_performance_report gkpr
        JOIN campaign_main_report_type cmrt 
            ON cmrt.id_campaign = gkpr.id_campaign 
            AND cmrt.report_type = 'keywords_performance_report'
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
),

ads_costs AS (
    SELECT
        INT(REPLACE(gapr.dt_loaded, '-', '')) AS id_date,
        gapr.campaign_name,
        LOWER(
            CASE WHEN SPLIT(gapr.campaign_name, '\\.')[1] RLIKE '[0-9]+$' THEN
                SPLIT(gapr.campaign_name, '\\.')[2]
            ELSE
                SPLIT(gapr.campaign_name, '\\.')[1]
            END
        ) AS campaign_city,
        gapr.account_descriptive_name AS account_name,
        cmrt.report_type,
        COALESCE(ad_types.flag, 'other') AS ad_type,
        STRING(ad_group_name) AS utm_term,
        STRING(id_ad) AS utm_content,
        gapr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'Computers' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('Mobile devices with full browsers', 'Tablets with full browsers') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost
    FROM
        datalake_google_ads_clean.ads_performance_report gapr
        JOIN campaign_main_report_type cmrt 
            ON cmrt.id_campaign = gapr.id_campaign 
            AND cmrt.report_type = 'ads_performance_report'
        LEFT JOIN datalake_gsheets_clean.marketing_costs_google_ad_type_flags ad_types
            ON ad_types.ad_type = gapr.ad_type
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
),

campaigns_costs AS (
    SELECT
        INT(REPLACE(gcpr.dt_loaded, '-', '')) AS id_date,
        gcpr.campaign_name,
        LOWER(
            CASE WHEN SPLIT(gcpr.campaign_name, '\\.')[1] RLIKE '[0-9]+$' THEN
                SPLIT(gcpr.campaign_name, '\\.')[2]
            ELSE
                SPLIT(gcpr.campaign_name, '\\.')[1]
            END
        ) AS campaign_city,
        gcpr.account_descriptive_name AS account_name,
        cmrt.report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        gcpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'Computers' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('Mobile devices with full browsers', 'Tablets with full browsers') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost
    FROM
        datalake_google_ads_clean.campaigns_performance_report gcpr
        JOIN campaign_main_report_type cmrt 
            ON cmrt.id_campaign = gcpr.id_campaign 
            AND cmrt.report_type = 'campaigns_performance_report'
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
),

videos_costs AS (
    SELECT
        INT(REPLACE(gvpr.dt_loaded, '-', '')) AS id_date,
        gvpr.campaign_name,
        LOWER(
            CASE WHEN SPLIT(gvpr.campaign_name, '\\.')[1] RLIKE '[0-9]+$' THEN
                SPLIT(gvpr.campaign_name, '\\.')[2]
            ELSE
                SPLIT(gvpr.campaign_name, '\\.')[1]
            END
        ) AS campaign_city,
        gvpr.account_descriptive_name AS account_name,
        cmrt.report_type,
        NULL AS ad_type,
        NULL AS utm_term,
        NULL AS utm_content,
        gvpr.campaign_name AS utm_campaign,
        SUM(CASE
            WHEN device = 'Computers' THEN cost/1000000
            ELSE 0
        END) AS desktop_cost,
        SUM(CASE
            WHEN device IN ('Mobile devices with full browsers', 'Tablets with full browsers') THEN cost/1000000
            ELSE 0
        END) AS mobile_cost,
        SUM(cost/1000000) AS total_cost
    FROM
        datalake_google_ads_clean.videos_performance_report gvpr
        JOIN campaign_main_report_type cmrt 
            ON cmrt.id_campaign = gvpr.id_campaign 
            AND cmrt.report_type = 'videos_performance_report'
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY
        1,2,3,4,5,6,7,8
)

SELECT * FROM keywords_costs
UNION ALL
SELECT * FROM ads_costs
UNION ALL
SELECT * FROM campaigns_costs
UNION ALL
SELECT * FROM videos_costs