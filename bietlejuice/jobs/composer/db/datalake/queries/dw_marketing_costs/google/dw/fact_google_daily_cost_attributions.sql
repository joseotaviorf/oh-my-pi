-- ADS START

WITH computer_devices_ads AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_ad, campaign_name, ad_group_name, device), 256) AS id,
        id_ad,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(coalesce(cast(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(coalesce(cast(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        SUM(coalesce(cast(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
mobile_devices_ads AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_ad, campaign_name, ad_group_name, device), 256) AS id,
        id_ad,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(coalesce(cast(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(coalesce(cast(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        SUM(coalesce(cast(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
tablet_devices_ads AS (
    SELECT
        SHA2(CONCAT(id_external_customer, id_ad, campaign_name, ad_group_name, device), 256) AS id,
        id_ad,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(coalesce(cast(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(coalesce(cast(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        SUM(coalesce(cast(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
cte_ads AS (
    SELECT 
        SHA2(CONCAT(gads.id_external_customer, gads.id_ad, gads.campaign_name, gads.ad_group_name, gads.device), 256) AS id,
        CAST(REPLACE(gads.dt_loaded, '-', '') AS INTEGER) AS sk_date,
        BIGINT(gads.id_ad),
        gads.id_external_customer,
        gads.id_campaign,
        gads.id_ad_group,
        gads.account_descriptive_name,
        gads.account_snake_case,
        gads.campaign_name,
        gads.ad_group_name,
        gads.ad_type,
        COALESCE(mobile_devices_ads.total_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_devices_ads.total_clicks, 0) AS tablet_clicks,
        COALESCE(computer_devices_ads.total_clicks, 0) AS computer_clicks,
        (COALESCE(mobile_devices_ads.total_clicks, 0) + COALESCE(tablet_devices_ads.total_clicks, 0) + COALESCE(computer_devices_ads.total_clicks, 0)) AS total_clicks,
        (COALESCE(mobile_devices_ads.total_cost, 0) + COALESCE(tablet_devices_ads.total_cost, 0)) AS mobile_cost,
        COALESCE(computer_devices_ads.total_cost, 0) AS desktop_cost,
        (COALESCE(mobile_devices_ads.total_cost, 0) + COALESCE(tablet_devices_ads.total_cost, 0) + COALESCE(computer_devices_ads.total_cost, 0)) AS total_cost,
        COALESCE(mobile_devices_ads.impressions, 0) AS mobile_impressions,
        COALESCE(tablet_devices_ads.impressions, 0) AS tablet_impressions,
        COALESCE(computer_devices_ads.impressions, 0) AS desktop_impressions,
        (COALESCE(mobile_devices_ads.impressions, 0) + COALESCE(tablet_devices_ads.impressions, 0) + COALESCE(computer_devices_ads.impressions, 0)) AS impressions,
        gads.dt_loaded
    FROM 
        datalake_google_ads_clean.ads_performance_report gads
        LEFT JOIN computer_devices_ads
            ON computer_devices_ads.id = gads.id
            AND computer_devices_ads.dt_loaded = gads.dt_loaded
        LEFT JOIN mobile_devices_ads
            ON mobile_devices_ads.id = gads.id
            AND mobile_devices_ads.dt_loaded = gads.dt_loaded
        LEFT JOIN tablet_devices_ads
            ON tablet_devices_ads.id = gads.id
            AND tablet_devices_ads.dt_loaded = gads.dt_loaded
        WHERE
            gads.dt_loaded = DATE('{year}-{month}-{day}')
), 
final_cte_ads AS (
    SELECT
        cte_ads.sk_date,
        '-1' AS sk_keyword,
        FIRST(cte_ads.id) AS sk_ad,
        '-1' AS sk_campaign,
        '-1' AS sk_video,
        cte_ads.id_ad,
        BIGINT(-1) AS id_keyword,
        cte_ads.id_external_customer,
        cte_ads.id_campaign,
        cte_ads.id_ad_group,
        SUM(cte_ads.mobile_clicks) AS mobile_clicks,
        SUM(cte_ads.tablet_clicks) AS tablet_clicks,
        SUM(cte_ads.computer_clicks) AS computer_clicks,
        SUM(cte_ads.total_clicks) AS total_clicks,
        SUM(cte_ads.mobile_cost) AS mobile_cost,
        SUM(cte_ads.desktop_cost) AS desktop_cost,
        SUM(cte_ads.total_cost) AS total_cost,
        SUM(cte_ads.mobile_impressions) AS mobile_impressions,
        SUM(cte_ads.tablet_impressions) AS tablet_impressions,
        SUM(cte_ads.desktop_impressions) AS desktop_impressions,
        SUM(cte_ads.impressions) AS impressions,
        NOW() AS ts_load,
        cte_ads.dt_loaded
    FROM 
        cte_ads
        LEFT JOIN dw_marketing_costs_staging.dim_google_ad dim
            ON dim.sk_ad = cte_ads.id
    GROUP BY 
        1,2,4,5,6,7,8,9,10,22,23
),

-- ADS END
-- KEYWORDS START

computer_devices_keywords AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_keyword, campaign_name, ad_group_name, device), 256) AS id,
        id_keyword,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        MAX(COALESCE(CAST(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
mobile_devices_keywords AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_keyword, campaign_name, ad_group_name, device), 256) AS id,
        id_keyword,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        MAX(COALESCE(CAST(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
tablet_devices_keywords AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_keyword, campaign_name, ad_group_name, device), 256) AS id,
        id_keyword,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        MAX(COALESCE(CAST(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
cte_keywords AS (
    SELECT 
        SHA2(CONCAT(gads.d_external_customer, gads.id_keyword, gads.campaign_name, gads.ad_group_name, gads.device), 256) AS id,
        CAST(replace(gads.dt_loaded, '-', '') AS INTEGER) AS sk_date,
        gads.id_keyword,
        gads.id_external_customer,
        gads.id_campaign,
        gads.id_ad_group,
        gads.account_descriptive_name,
        gads.account_snake_case,
        gads.campaign_name,
        gads.ad_group_name,
        gads.match_type,
        COALESCE(mobile_devices_keywords.total_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_devices_keywords.total_clicks, 0) AS tablet_clicks,
        COALESCE(computer_devices_keywords.total_clicks, 0) AS computer_clicks,
        (COALESCE(mobile_devices_keywords.total_clicks, 0) + COALESCE(tablet_devices_keywords.total_clicks, 0) + COALESCE(computer_devices_keywords.total_clicks, 0)) AS total_clicks,
        (COALESCE(mobile_devices_keywords.total_cost, 0) + COALESCE(tablet_devices_keywords.total_cost, 0)) AS mobile_cost,
        COALESCE(computer_devices_keywords.total_cost, 0) AS desktop_cost,
        (COALESCE(mobile_devices_keywords.total_cost, 0) + COALESCE(tablet_devices_keywords.total_cost, 0) + COALESCE(computer_devices_keywords.total_cost, 0)) AS total_cost,
        COALESCE(mobile_devices_keywords.impressions, 0)  AS mobile_impressions,
        COALESCE(tablet_devices_keywords.impressions, 0)  AS tablet_impressions,
        COALESCE(computer_devices_keywords.impressions, 0)  AS desktop_impressions,
        (COALESCE(mobile_devices_keywords.impressions, 0) + COALESCE(tablet_devices_keywords.impressions, 0) + COALESCE(computer_devices_keywords.impressions, 0)) AS impressions,
        gads.dt_loaded
FROM 
    datalake_google_ads_clean.keywords_performance_report gads
    LEFT JOIN computer_devices_keywords
        ON computer_devices_keywords.id = gads.id
        AND computer_devices_keywords.dt_loaded = gads.dt_loaded
    LEFT JOIN mobile_devices_keywords
        ON mobile_devices_keywords.id = gads.id
        AND mobile_devices_keywords.dt_loaded = gads.dt_loaded
    LEFT JOIN tablet_devices_keywords
        ON tablet_devices_keywords.id = gads.id
        AND tablet_devices_keywords.dt_loaded = gads.dt_loaded
WHERE 
    gads.dt_loaded = DATE('{year}-{month}-{day}')
), 
final_cte_keywords AS (
    SELECT
        cte_keywords.sk_date,
        FIRST(cte_keywords.id) AS sk_keyword,
        '-1' AS sk_ad,
        '-1' AS sk_campaign,
        '-1' AS sk_video,
        BIGINT(-1) AS id_ad,
        cte_keywords.id_keyword,
        cte_keywords.id_external_customer,
        cte_keywords.id_campaign,
        cte_keywords.id_ad_group,
        SUM(cte_keywords.mobile_clicks) AS mobile_clicks,
        SUM(cte_keywords.tablet_clicks) AS tablet_clicks,
        SUM(cte_keywords.computer_clicks) AS computer_clicks,
        SUM(cte_keywords.total_clicks) AS total_clicks,
        SUM(cte_keywords.mobile_cost) AS mobile_cost,
        SUM(cte_keywords.desktop_cost) AS desktop_cost,
        SUM(cte_keywords.total_cost) AS total_cost,
        SUM(cte_keywords.mobile_impressions) AS mobile_impressions,
        SUM(cte_keywords.tablet_impressions) AS tablet_impressions,
        SUM(cte_keywords.desktop_impressions) AS desktop_impressions,
        SUM(cte_keywords.impressions) AS impressions,
        NOW() AS ts_load,
        cte_keywords.dt_loaded
    FROM 
        cte_keywords
        LEFT JOIN dw_marketing_costs_staging.dim_google_keyword dim
            ON dim.sk_keyword = cte_keywords.id
    GROUP BY
        1,3,4,5,6,7,8,9,10,22,23
),

-- KEYWORDS END
-- CAMPAIGNS START

computer_devices_campaigns AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS id,
        id_campaign,
        id_external_customer,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS integer), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS float), 0)) / 1000000 AS total_cost,
        MAX(COALESCE(CAST(impressions AS integer), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,9,10
),
mobile_devices_campaigns AS (
    SELECT 
        SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS id,
        id_campaign,
        id_external_customer,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS integer), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS float), 0)) / 1000000 AS total_cost,
        MAX(COALESCE(CAST(impressions AS integer), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = date('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,9,10
),
tablet_devices_campaigns AS (
    SELECT
        SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS id,
        id_campaign,
        id_external_customer,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS integer), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS float), 0)) / 1000000 AS total_cost,
        MAX(COALESCE(CAST(impressions AS integer), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = date('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,9,10
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
        COALESCE(mobile_devices_campaigns.total_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_devices_campaigns.total_clicks, 0) AS tablet_clicks,
        COALESCE(computer_devices_campaigns.total_clicks, 0) AS computer_clicks,
        (COALESCE(mobile_devices_campaigns.total_clicks, 0) + COALESCE(tablet_devices_campaigns.total_clicks, 0) + COALESCE(computer_devices_campaigns.total_clicks, 0)) AS total_clicks,
        (COALESCE(mobile_devices_campaigns.total_cost, 0) + COALESCE(tablet_devices_campaigns.total_cost, 0)) AS mobile_cost,
        COALESCE(computer_devices_campaigns.total_cost, 0) AS desktop_cost,
        (COALESCE(mobile_devices_campaigns.total_cost, 0) + COALESCE(tablet_devices_campaigns.total_cost, 0) + COALESCE(computer_devices_campaigns.total_cost, 0)) AS total_cost,
        COALESCE(mobile_devices_campaigns.impressions, 0) AS mobile_impressions,
        COALESCE(tablet_devices_campaigns.impressions, 0) AS tablet_impressions,
        COALESCE(computer_devices_campaigns.impressions, 0) AS desktop_impressions,
        (COALESCE(mobile_devices_campaigns.impressions, 0) + COALESCE(tablet_devices_campaigns.impressions, 0) + COALESCE(computer_devices_campaigns.impressions, 0)) AS impressions,
        gads.dt_loaded
FROM 
    datalake_google_ads_clean.campaigns_performance_report gads
    LEFT JOIN computer_devices_campaigns
        ON computer_devices_campaigns.id = gads.id
        AND computer_devices_campaigns.dt_loaded = gads.dt_loaded
    LEFT JOIN mobile_devices_campaigns
        ON mobile_devices_campaigns.id = gads.id
        AND mobile_devices_campaigns.dt_loaded = gads.dt_loaded
    LEFT JOIN tablet_devices_campaigns
        ON tablet_devices_campaigns.id = gads.id
        AND tablet_devices_campaigns.dt_loaded = gads.dt_loaded
WHERE
    gads.dt_loaded = date('{year}-{month}-{day}')
),
final_cte_campaigns as (
    SELECT
        cte_campaigns.sk_date,
        '-1' AS sk_keyword,
        '-1' AS sk_ad,
        FIRST(cte_campaigns.id) AS sk_campaign,
        '-1' AS sk_video,
        BIGINT(-1) AS id_ad,
        BIGINT(-1) AS id_keyword,
        cte_campaigns.id_external_customer,
        cte_campaigns.id_campaign,
        'null' AS adgroup_id,
        SUM(cte_campaigns.mobile_clicks) AS mobile_clicks,
        SUM(cte_campaigns.tablet_clicks) AS tablet_clicks,
        SUM(cte_campaigns.computer_clicks) AS computer_clicks,
        SUM(cte_campaigns.total_clicks) AS total_clicks,
        SUM(cte_campaigns.mobile_cost) AS mobile_cost,
        SUM(cte_campaigns.desktop_cost) AS desktop_cost,
        SUM(cte_campaigns.total_cost) AS total_cost,
        SUM(cte_campaigns.mobile_impressions) AS mobile_impressions,
        SUM(cte_campaigns.tablet_impressions) AS tablet_impressions,
        SUM(cte_campaigns.desktop_impressions) AS desktop_impressions,
        SUM(cte_campaigns.impressions) AS impressions,
        now() AS ts_load,
        cte_campaigns.dt_loaded
    FROM 
        cte_campaigns
        LEFT JOIN dw_marketing_costs_staging.dim_google_campaign dim
            ON dim.sk_campaign = cte_campaigns.id
    GROUP BY
        1,2,3,5,6,7,8,9,10,22,23
),

-- CAMPAIGNS END
-- VIDEOS START

computer_devices_videos AS (
    SELECT 
	    SHA2(CONCAT(id_external_customer, id_video, campaign_name, ad_group_name, device), 256) AS id,
        id_video,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE 
        device = 'Computers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
mobile_devices_videos AS (
    SELECT 
	    SHA2(CONCAT(id_external_customer, id_video, campaign_name, ad_group_name, device), 256) AS id,
        id_video,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE 
        device = 'Mobile devices with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
tablet_devices_videos AS (
    SELECT 
	    SHA2(CONCAT(id_external_customer, id_video, campaign_name, ad_group_name, device), 256) AS id,
        id_video,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(CAST(clicks AS INTEGER), 0)) AS total_clicks,
        SUM(COALESCE(CAST(cost AS FLOAT), 0)) / 1000000 AS total_cost,
        SUM(COALESCE(CAST(impressions AS INTEGER), 0)) AS impressions,
        dt_loaded
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE 
        device = 'Tablets with full browsers'
        AND dt_loaded = DATE('{year}-{month}-{day}')
    GROUP BY 
        1,2,3,4,5,6,7,11,12
),
cte_videos AS (
    SELECT 
	    SHA2(CONCAT(gads.id_external_customer, gads.id_video, gads.campaign_name, gads.ad_group_name, gads.device), 256) AS id,
        CAST(REPLACE(gads.dt_loaded, '-', '') AS INTEGER) AS sk_date,
        gads.id_video,
        gads.id_external_customer,
        gads.id_campaign,
        gads.id_ad_group,
        gads.account_descriptive_name,
        gads.account_snake_case,
        gads.campaign_name,
        gads.ad_group_name,
        COALESCE(mobile_devices_videos.total_clicks, 0) AS mobile_clicks,
        COALESCE(tablet_devices_videos.total_clicks, 0) AS tablet_clicks,
        COALESCE(computer_devices_videos.total_clicks, 0) AS computer_clicks,
        (COALESCE(mobile_devices_videos.total_clicks, 0) + COALESCE(tablet_devices_videos.total_clicks, 0) + COALESCE(computer_devices_videos.total_clicks, 0)) AS total_clicks,
        (COALESCE(mobile_devices_videos.total_cost, 0) + COALESCE(tablet_devices_videos.total_cost, 0)) AS mobile_cost,
        COALESCE(computer_devices_videos.total_cost, 0) AS desktop_cost,
        (COALESCE(mobile_devices_videos.total_cost, 0) + COALESCE(tablet_devices_videos.total_cost, 0) + COALESCE(computer_devices_videos.total_cost, 0)) AS total_cost,
        COALESCE(mobile_devices_videos.impressions, 0) AS mobile_impressions,
        COALESCE(tablet_devices_videos.impressions, 0) AS tablet_impressions,
        COALESCE(computer_devices_videos.impressions, 0) AS desktop_impressions,
        (COALESCE(mobile_devices_videos.impressions, 0) + COALESCE(tablet_devices_videos.impressions, 0) + COALESCE(computer_devices_videos.impressions, 0)) AS impressions,
        gads.dt_loaded
FROM datalake_google_ads_clean.videos_performance_report gads
    LEFT JOIN computer_devices_videos
        ON computer_devices_videos.id = gads.id
        AND computer_devices_videos.dt_loaded = gads.dt_loaded
    LEFT JOIN mobile_devices_videos
        ON mobile_devices_videos.id = gads.id
        AND mobile_devices_videos.dt_loaded = gads.dt_loaded
    LEFT JOIN tablet_devices_videos
        ON tablet_devices_videos.id = gads.id
        AND tablet_devices_videos.dt_loaded = gads.dt_loaded
WHERE
    gads.dt_loaded = DATE('{year}-{month}-{day}')
),
final_cte_videos AS (
    SELECT 
        cte_videos.sk_date,
        '-1' AS sk_keyword,
        '-1' AS sk_ad,
        '-1' AS sk_campaign,
        FIRST(dim.sk_video) AS sk_video,
        BIGINT(-1) AS id_ad,
        BIGINT(-1) AS id_keyword,
        cte_videos.id_external_customer,
        cte_videos.id_campaign,
        cte_videos.id_ad_group,
        SUM(cte_videos.mobile_clicks) AS mobile_clicks,
        SUM(cte_videos.tablet_clicks) AS tablet_clicks,
        SUM(cte_videos.computer_clicks) AS computer_clicks,
        SUM(cte_videos.total_clicks) AS total_clicks,
        SUM(cte_videos.mobile_cost) AS mobile_cost,
        SUM(cte_videos.desktop_cost) AS desktop_cost,
        SUM(cte_videos.total_cost) AS total_cost,
        SUM(cte_videos.mobile_impressions) AS mobile_impressions,
        SUM(cte_videos.tablet_impressions) AS tablet_impressions,
        SUM(cte_videos.desktop_impressions) AS desktop_impressions,
        SUM(cte_videos.impressions) AS impressions,
        NOW() AS ts_load,
        cte_videos.dt_loaded
    FROM 
        cte_videos
        LEFT JOIN dw_marketing_costs_staging.dim_google_video dim
            ON dim.sk_video = cte_videos.id
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