WITH clean_table_common AS (
    SELECT DISTINCT
	    SHA2(CONCAT(id_external_customer, id_video, id_campaign, id_ad_group, device), 256) AS sk_video,
        id_video,
        ad_group_name,
        campaign_name,
        device,
        account_snake_case AS account_name,
        account_descriptive_name,
        report_type,
        (campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
        dt_loaded
    FROM 
        datalake_google_ads_clean.videos_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
)
SELECT 
    clean_table_common.*,
    NOW() AS ts_load
FROM 
    clean_table_common
    LEFT JOIN dw_google_ads.dim_google_video st_dim
        ON clean_table_common.sk_video = st_dim.sk_video
WHERE 
    st_dim.sk_video IS NULL
