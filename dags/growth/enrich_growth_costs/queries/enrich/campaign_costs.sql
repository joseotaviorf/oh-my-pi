WITH cost AS (
    SELECT 
        dates.date,
        dates.week_start,
        dates.year_month,
        dates.sk_date,
        media_metrics.sk_campaign,
        media_metrics.utm_campaign AS nm_campaign,
        media_metrics.sk_adset,
        media_metrics.dt_cost,
        media_metrics.origin,
        media_metrics.country_code,
        COALESCE(LOWER(sharing.business_context), setup.campaign_business_context) AS nm_business_context,
        region.city_group,
        sharing.share,
        SUM(media_metrics.clicks) AS clicks,
        SUM(media_metrics.conversions) AS conversions,
        SUM(media_metrics.impressions) AS impressions,
        SUM(media_metrics.total_cost) AS total_cost,
        SUM(total_cost * COALESCE(share, 1)) AS share_cost,
        SUM(impressions * COALESCE(share, 1)) AS share_impressions,
        SUM(clicks * COALESCE(share, 1)) AS share_clicks,
        media_metrics.year,
        media_metrics.month,
        media_metrics.day
    FROM
        dw_growth.fact_media_platform_metrics AS media_metrics
    LEFT JOIN
        dw_growth.dim_sharing_rules AS sharing
            ON sharing.bk_sharing_rules = media_metrics.bk_sharing_rules
            AND utm_campaign_modified = SUBSTRING(media_metrics.utm_campaign, POSITION('.' IN media_metrics.utm_campaign) + 1)
    LEFT JOIN
        dw_public.dim_region AS region
            ON region.sk_region = media_metrics.sk_region
    LEFT JOIN
        dw_growth.dim_media_setup AS setup
            ON setup.naming_convention_sufix = media_metrics.naming_convention_sufix
    JOIN
        dw_public.dim_date AS dates
            ON dates.sk_date = media_metrics.sk_cost_date
    WHERE
        media_metrics.dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE
    GROUP BY ALL
),
-- Google Ads campaign totals aggregated by campaign and date
campaign_google_total AS (
    SELECT 
        id_campaign,
        BIGINT(DATE_FORMAT(dt_created, 'yyyyMMdd')) AS sk_date,
        SUM(clicks) AS clicks,
        SUM(conversions) AS conversions,
        SUM(impressions) AS impressions,
        SUM((cost / 1000000)) AS total_cost
    FROM
        datalake_google_ads_clean.campaigns_performance 
    GROUP BY ALL
),
-- Google campaign data with geo-targeting breakdown
campaign_google_geo_total AS (
    SELECT 
        date,
        week_start,
        year_month,
        sk_date,
        sk_campaign,
        nm_campaign,
        dt_cost,
        origin,
        country_code,
        nm_business_context,
        SUM(clicks) AS clicks,
        SUM(conversions) AS conversions,
        SUM(impressions) AS impressions,
        SUM(total_cost) AS total_cost,
        year,
        month,
        day
    FROM 
        cost
    WHERE
        origin = 'google'
    GROUP BY ALL
)
-- Main result combining cost data with Google geo-targeting differences
SELECT 
        date,
        week_start,
        year_month,
        sk_date,
        sk_campaign,
        nm_campaign,
        sk_adset,
        dt_cost,
        origin,
        country_code,
        nm_business_context,
        city_group,
        share,
        clicks,
        conversions,
        impressions,
        total_cost,
        share_cost,
        share_impressions,
        share_clicks,
        year,
        month,
        day
FROM 
    cost 
UNION ALL 
SELECT
    google_geo.date,
    google_geo.week_start,
    google_geo.year_month,
    google_geo.sk_date,
    google_geo.sk_campaign,
    google_geo.nm_campaign,
    NULL AS sk_adset,
    google_geo.dt_cost,
    google_geo.origin,
    google_geo.country_code,
    google_geo.nm_business_context,
    'N/A' AS city_group,
    1 AS share,
    google_total.clicks - google_geo.clicks AS clicks,
    google_total.conversions - google_geo.conversions AS conversions,
    google_total.impressions - google_geo.impressions AS impressions,
    google_total.total_cost - google_geo.total_cost AS total_cost,
    google_total.clicks - google_geo.clicks AS share_clicks,
    google_total.impressions - google_geo.impressions AS share_impressions,
    google_total.total_cost - google_geo.total_cost AS share_cost,
    google_geo.year,
    google_geo.month,
    google_geo.day
FROM
    campaign_google_geo_total AS google_geo
INNER JOIN
    campaign_google_total AS google_total
        ON google_geo.sk_campaign = google_total.id_campaign
        AND google_geo.sk_date = google_total.sk_date
WHERE
    google_geo.dt_cost::DATE BETWEEN '{load_start_date}'::DATE AND '{load_end_date}'::DATE