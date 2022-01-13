SELECT 
    id_date AS sk_date,
    origin,
    account_name,
    city_group,
    report_type,
    ad_type,
    utm_campaign,
    utm_term,
    utm_content,
    CAST(desktop_cost AS FLOAT8) AS desktop_cost,
    CAST(mobile_cost AS FLOAT8) AS mobile_cost,
    CAST(other_cost AS FLOAT8) AS other_cost,
    CAST(total_cost AS FLOAT8) AS total_cost,
    CAST(impressions AS INT) AS impressions,
    CAST(clicks AS INT) AS clicks
FROM 
    datalake_consolidated_marketing_metrics_prod.consolidated_media_metrics
