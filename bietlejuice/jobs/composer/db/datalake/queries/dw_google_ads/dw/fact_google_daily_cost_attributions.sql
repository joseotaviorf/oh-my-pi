-- ADS START

WITH computer_devices_ads AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_ad, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS computer_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS computer_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS computer_impressions
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
mobile_devices_ads AS (
    SELECT
        SHA2(CONCAT(id_external_customer, id_ad, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS mobile_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS mobile_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS mobile_impressions
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
tablet_devices_ads AS (
    SELECT
        SHA2(CONCAT(id_external_customer, id_ad, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS tablet_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS tablet_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS tablet_impressions
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
cte_ads AS (
    SELECT 
        SHA2(CONCAT(gads.id_external_customer, gads.id_ad, gads.id_campaign, gads.id_ad_group, gads.device), 256) AS id,
        CAST(REPLACE(gads.dt_loaded, '-', '') AS INTEGER) AS sk_date,
        BIGINT(gads.id_ad) AS id_ad,
        gads.id_external_customer,
        gads.id_campaign,
        gads.id_ad_group,
        gads.account_descriptive_name,
        gads.account_snake_case,
        gads.campaign_name,
        gads.ad_group_name,
        gads.ad_type,
        COALESCE(mobile_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_clicks, 0) AS tablet_clicks,
        COALESCE(computer_clicks, 0) AS computer_clicks,
        COALESCE(mobile_clicks, 0) + COALESCE(tablet_clicks, 0) + COALESCE(computer_clicks, 0) AS total_clicks,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) AS mobile_cost,
        COALESCE(computer_cost, 0) AS desktop_cost,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) + COALESCE(computer_cost, 0) AS total_cost,
        COALESCE(mobile_impressions, 0) AS mobile_impressions,
        COALESCE(tablet_impressions, 0) AS tablet_impressions,
        COALESCE(computer_impressions, 0) AS desktop_impressions,
        COALESCE(mobile_impressions, 0) + COALESCE(tablet_impressions, 0) + COALESCE(computer_impressions, 0) AS impressions,
        gads.dt_loaded
    FROM 
        datalake_google_ads_clean.ads_performance_report gads
        LEFT JOIN computer_devices_ads
            ON computer_devices_ads.id = SHA2(CONCAT(gads.id_external_customer, gads.id_ad, gads.id_campaign, gads.id_ad_group, gads.device), 256)
            AND computer_devices_ads.dt_loaded = gads.dt_loaded
        LEFT JOIN mobile_devices_ads
            ON mobile_devices_ads.id = SHA2(CONCAT(gads.id_external_customer, gads.id_ad, gads.id_campaign, gads.id_ad_group, gads.device), 256)
            AND mobile_devices_ads.dt_loaded = gads.dt_loaded
        LEFT JOIN tablet_devices_ads
            ON tablet_devices_ads.id = SHA2(CONCAT(gads.id_external_customer, gads.id_ad, gads.id_campaign, gads.id_ad_group, gads.device), 256)
            AND tablet_devices_ads.dt_loaded = gads.dt_loaded
        WHERE
            gads.dt_loaded = DATE('{year}-{month}-{day}')
), 
final_cte_ads AS (
    SELECT
        sk_date,
        '-1' AS sk_keyword,
        FIRST(id) AS sk_ad,
        '-1' AS sk_campaign,
        '-1' AS sk_video,
        id_ad,
        BIGINT(-1) AS id_keyword,
        id_external_customer,
        id_campaign,
        id_ad_group,
        SUM(mobile_clicks) AS mobile_clicks,
        SUM(tablet_clicks) AS tablet_clicks,
        SUM(computer_clicks) AS computer_clicks,
        SUM(total_clicks) AS total_clicks,
        SUM(mobile_cost) AS mobile_cost,
        SUM(desktop_cost) AS desktop_cost,
        SUM(total_cost) AS total_cost,
        SUM(mobile_impressions) AS mobile_impressions,
        SUM(tablet_impressions) AS tablet_impressions,
        SUM(desktop_impressions) AS desktop_impressions,
        SUM(impressions) AS impressions,
        NOW() AS ts_load,
        dt_loaded
    FROM 
        cte_ads
    GROUP BY 
        1,2,4,5,6,7,8,9,10,22,23
),

-- ADS END
-- KEYWORDS START

computer_devices_keywords AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_keyword, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS computer_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS computer_cost,
        MAX(COALESCE(CAST(impressions AS INTEGER), 0)) AS computer_impressions
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
mobile_devices_keywords AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_keyword, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS mobile_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS mobile_cost,
        MAX(COALESCE(CAST(impressions AS INTEGER), 0)) AS mobile_impressions
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
tablet_devices_keywords AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_keyword, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS tablet_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS tablet_cost,
        MAX(COALESCE(CAST(impressions AS INTEGER), 0)) AS tablet_impressions
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
cte_keywords AS (
    SELECT 
        SHA2(CONCAT(gads.id_external_customer, gads.id_keyword, gads.id_campaign, gads.id_ad_group, gads.device), 256) AS id,
        CAST(REPLACE(gads.dt_loaded, '-', '') AS INTEGER) AS sk_date,
        gads.id_keyword,
        gads.id_external_customer,
        gads.id_campaign,
        gads.id_ad_group,
        gads.account_descriptive_name,
        gads.account_snake_case,
        gads.campaign_name,
        gads.ad_group_name,
        gads.match_type,
        COALESCE(mobile_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_clicks, 0) AS tablet_clicks,
        COALESCE(computer_clicks, 0) AS computer_clicks,
        COALESCE(mobile_clicks, 0) + COALESCE(tablet_clicks, 0) + COALESCE(computer_clicks, 0) AS total_clicks,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) AS mobile_cost,
        COALESCE(computer_cost, 0) AS desktop_cost,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) + COALESCE(computer_cost, 0) AS total_cost,
        COALESCE(mobile_impressions, 0) AS mobile_impressions,
        COALESCE(tablet_impressions, 0) AS tablet_impressions,
        COALESCE(computer_impressions, 0) AS desktop_impressions,
        COALESCE(mobile_impressions, 0) + COALESCE(tablet_impressions, 0) + COALESCE(computer_impressions, 0) AS impressions,
        gads.dt_loaded
FROM 
    datalake_google_ads_clean.keywords_performance_report gads
    LEFT JOIN computer_devices_keywords
        ON computer_devices_keywords.id = SHA2(CONCAT(gads.id_external_customer, gads.id_keyword, gads.id_campaign, gads.id_ad_group, gads.device), 256)
        AND computer_devices_keywords.dt_loaded = gads.dt_loaded
    LEFT JOIN mobile_devices_keywords
        ON mobile_devices_keywords.id = SHA2(CONCAT(gads.id_external_customer, gads.id_keyword, gads.id_campaign, gads.id_ad_group, gads.device), 256)
        AND mobile_devices_keywords.dt_loaded = gads.dt_loaded
    LEFT JOIN tablet_devices_keywords
        ON tablet_devices_keywords.id = SHA2(CONCAT(gads.id_external_customer, gads.id_keyword, gads.id_campaign, gads.id_ad_group, gads.device), 256)
        AND tablet_devices_keywords.dt_loaded = gads.dt_loaded
WHERE 
    gads.dt_loaded = DATE('{year}-{month}-{day}')
), 
final_cte_keywords AS (
    SELECT
        sk_date,
        FIRST(id) AS sk_keyword,
        '-1' AS sk_ad,
        '-1' AS sk_campaign,
        '-1' AS sk_video,
        BIGINT(-1) AS id_ad,
        id_keyword,
        id_external_customer,
        id_campaign,
        id_ad_group,
        SUM(mobile_clicks) AS mobile_clicks,
        SUM(tablet_clicks) AS tablet_clicks,
        SUM(computer_clicks) AS computer_clicks,
        SUM(total_clicks) AS total_clicks,
        SUM(mobile_cost) AS mobile_cost,
        SUM(desktop_cost) AS desktop_cost,
        SUM(total_cost) AS total_cost,
        SUM(mobile_impressions) AS mobile_impressions,
        SUM(tablet_impressions) AS tablet_impressions,
        SUM(desktop_impressions) AS desktop_impressions,
        SUM(impressions) AS impressions,
        NOW() AS ts_load,
        dt_loaded
    FROM 
        cte_keywords
    GROUP BY
        1,3,4,5,6,7,8,9,10,22,23
),

-- KEYWORDS END
-- CAMPAIGNS START

computer_devices_campaigns AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS integer), 0)) AS computer_clicks,
        SUM(COALESCE(CAST(cost AS float), 0)) / 1000000 AS computer_cost,
        MAX(COALESCE(CAST(impressions AS integer), 0)) AS computer_impressions
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
mobile_devices_campaigns AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS integer), 0)) AS mobile_clicks,
        SUM(COALESCE(CAST(cost AS float), 0)) / 1000000 AS mobile_cost,
        MAX(COALESCE(CAST(impressions AS integer), 0)) AS mobile_impressions
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = date('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
tablet_devices_campaigns AS (
    SELECT
        SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS integer), 0)) AS tablet_clicks,
        SUM(COALESCE(CAST(cost AS float), 0)) / 1000000 AS tablet_cost,
        MAX(COALESCE(CAST(impressions AS integer), 0)) AS tablet_impressions
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = date('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
cte_campaigns AS (
    SELECT 
        SHA2(CONCAT(gads.id_external_customer, gads.id_campaign, gads.campaign_name, gads.device), 256) AS id,
        CAST(REPLACE(gads.dt_loaded, '-', '') AS integer) AS sk_date,
        gads.id_external_customer,
        gads.id_campaign,
        gads.account_descriptive_name,
        gads.account_snake_case,
        gads.campaign_name,
        COALESCE(mobile_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_clicks, 0) AS tablet_clicks,
        COALESCE(computer_clicks, 0) AS computer_clicks,
        COALESCE(mobile_clicks, 0) + COALESCE(tablet_clicks, 0) + COALESCE(computer_clicks, 0) AS total_clicks,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) AS mobile_cost,
        COALESCE(computer_cost, 0) AS desktop_cost,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) + COALESCE(computer_cost, 0) AS total_cost,
        COALESCE(mobile_impressions, 0) AS mobile_impressions,
        COALESCE(tablet_impressions, 0) AS tablet_impressions,
        COALESCE(computer_impressions, 0) AS desktop_impressions,
        COALESCE(mobile_impressions, 0) + COALESCE(tablet_impressions, 0) + COALESCE(computer_impressions, 0) AS impressions,
        gads.dt_loaded
FROM 
    datalake_google_ads_clean.campaigns_performance_report gads
    LEFT JOIN computer_devices_campaigns
        ON computer_devices_campaigns.id = SHA2(CONCAT(gads.id_external_customer, gads.id_campaign, gads.campaign_name, gads.device), 256)
        AND computer_devices_campaigns.dt_loaded = gads.dt_loaded
    LEFT JOIN mobile_devices_campaigns
        ON mobile_devices_campaigns.id = SHA2(CONCAT(gads.id_external_customer, gads.id_campaign, gads.campaign_name, gads.device), 256)
        AND mobile_devices_campaigns.dt_loaded = gads.dt_loaded
    LEFT JOIN tablet_devices_campaigns
        ON tablet_devices_campaigns.id = SHA2(CONCAT(gads.id_external_customer, gads.id_campaign, gads.campaign_name, gads.device), 256)
        AND tablet_devices_campaigns.dt_loaded = gads.dt_loaded
WHERE
    gads.dt_loaded = date('{year}-{month}-{day}')
),
final_cte_campaigns as (
    SELECT
        sk_date,
        '-1' AS sk_keyword,
        '-1' AS sk_ad,
        FIRST(id) AS sk_campaign,
        '-1' AS sk_video,
        BIGINT(-1) AS id_ad,
        BIGINT(-1) AS id_keyword,
        id_external_customer,
        id_campaign,
        'null' AS id_ad_group,
        SUM(mobile_clicks) AS mobile_clicks,
        SUM(tablet_clicks) AS tablet_clicks,
        SUM(computer_clicks) AS computer_clicks,
        SUM(total_clicks) AS total_clicks,
        SUM(mobile_cost) AS mobile_cost,
        SUM(desktop_cost) AS desktop_cost,
        SUM(total_cost) AS total_cost,
        SUM(mobile_impressions) AS mobile_impressions,
        SUM(tablet_impressions) AS tablet_impressions,
        SUM(desktop_impressions) AS desktop_impressions,
        SUM(impressions) AS impressions,
        now() AS ts_load,
        dt_loaded
    FROM 
        cte_campaigns
    GROUP BY
        1,2,3,5,6,7,8,9,10,22,23
),

-- CAMPAIGNS END
-- VIDEOS START

computer_devices_videos AS (
    SELECT 
	    SHA2(CONCAT(id_external_customer, id_video, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS computer_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS computer_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS computer_impressions
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
mobile_devices_videos AS (
    SELECT 
	    SHA2(CONCAT(id_external_customer, id_video, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS mobile_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS mobile_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS mobile_impressions
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
tablet_devices_videos AS (
    SELECT 
	    SHA2(CONCAT(id_external_customer, id_video, id_campaign, id_ad_group, device), 256) AS id,
        dt_loaded,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS tablet_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS tablet_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS tablet_impressions
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2
),
cte_videos AS (
    SELECT 
	    SHA2(CONCAT(gads.id_external_customer, gads.id_video, gads.id_campaign, gads.id_ad_group, gads.device), 256) AS id,
        CAST(REPLACE(gads.dt_loaded, '-', '') AS INTEGER) AS sk_date,
        gads.id_video,
        gads.id_external_customer,
        gads.id_campaign,
        gads.id_ad_group,
        gads.account_descriptive_name,
        gads.account_snake_case,
        gads.campaign_name,
        gads.ad_group_name,
        COALESCE(mobile_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_clicks, 0) AS tablet_clicks,
        COALESCE(computer_clicks, 0) AS computer_clicks,
        COALESCE(mobile_clicks, 0) + COALESCE(tablet_clicks, 0) + COALESCE(computer_clicks, 0) AS total_clicks,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) AS mobile_cost,
        COALESCE(computer_cost, 0) AS desktop_cost,
        COALESCE(mobile_cost, 0) + COALESCE(tablet_cost, 0) + COALESCE(computer_cost, 0) AS total_cost,
        COALESCE(mobile_impressions, 0) AS mobile_impressions,
        COALESCE(tablet_impressions, 0) AS tablet_impressions,
        COALESCE(computer_impressions, 0) AS desktop_impressions,
        COALESCE(mobile_impressions, 0) + COALESCE(tablet_impressions, 0) + COALESCE(computer_impressions, 0) AS impressions,
        gads.dt_loaded
FROM datalake_google_ads_clean.videos_performance_report gads
    LEFT JOIN computer_devices_videos
        ON computer_devices_videos.id = SHA2(CONCAT(gads.id_external_customer, gads.id_video, gads.id_campaign, gads.id_ad_group, gads.device), 256)
        AND computer_devices_videos.dt_loaded = gads.dt_loaded
    LEFT JOIN mobile_devices_videos
        ON mobile_devices_videos.id = SHA2(CONCAT(gads.id_external_customer, gads.id_video, gads.id_campaign, gads.id_ad_group, gads.device), 256)
        AND mobile_devices_videos.dt_loaded = gads.dt_loaded
    LEFT JOIN tablet_devices_videos
        ON tablet_devices_videos.id = SHA2(CONCAT(gads.id_external_customer, gads.id_video, gads.id_campaign, gads.id_ad_group, gads.device), 256)
        AND tablet_devices_videos.dt_loaded = gads.dt_loaded
WHERE
    gads.dt_loaded = DATE('{year}-{month}-{day}')
),
final_cte_videos AS (
    SELECT 
        sk_date,
        '-1' AS sk_keyword,
        '-1' AS sk_ad,
        '-1' AS sk_campaign,
        FIRST(id) AS sk_video,
        BIGINT(-1) AS id_ad,
        BIGINT(-1) AS id_keyword,
        id_external_customer,
        id_campaign,
        id_ad_group,
        SUM(mobile_clicks) AS mobile_clicks,
        SUM(tablet_clicks) AS tablet_clicks,
        SUM(computer_clicks) AS computer_clicks,
        SUM(total_clicks) AS total_clicks,
        SUM(mobile_cost) AS mobile_cost,
        SUM(desktop_cost) AS desktop_cost,
        SUM(total_cost) AS total_cost,
        SUM(mobile_impressions) AS mobile_impressions,
        SUM(tablet_impressions) AS tablet_impressions,
        SUM(desktop_impressions) AS desktop_impressions,
        SUM(impressions) AS impressions,
        NOW() AS ts_load,
        dt_loaded
    FROM 
        cte_videos
    GROUP BY
        1,2,3,4,6,7,8,9,10,22,23
)

-- VIDEOS END

SELECT * FROM final_cte_keywords
UNION ALL
SELECT * FROM final_cte_ads
UNION ALL
SELECT * FROM final_cte_campaigns
UNION ALL
SELECT * FROM final_cte_videos