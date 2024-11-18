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
)

SELECT 
    *
FROM 
    all_metrics