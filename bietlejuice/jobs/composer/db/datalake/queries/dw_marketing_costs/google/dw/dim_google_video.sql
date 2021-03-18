WITH clean_table_common AS (
    SELECT
        FIRST(id) AS sk_video,
        id_video,
        ad_group_name,
        campaign_name,
        is_test_campaign,
        device,
        acc AS account_name,
        account_descriptive_name,
        report_type,
        load_date
    FROM 
        datalake_marketing_costs.google_videos_performance_report
    WHERE
        load_date = DATE('{year}-{month}-{day}')
    GROUP BY 2,3,4,5,6,7,8,9,10
)
SELECT 
    clean_table_common.*,
    NOW() AS ts_load
FROM clean_table_common
LEFT JOIN dw_marketing_costs_staging.dim_google_video st_dim
    ON clean_table_common.sk_video = st_dim.sk_video
WHERE st_dim.sk_video IS NULL
