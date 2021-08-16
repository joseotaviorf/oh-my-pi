WITH clean_table_common AS (
    SELECT DISTINCT
        SHA2(CONCAT(id_external_customer, id_ad, id_campaign, id_ad_group, device), 256) AS sk_ad,
        id_ad,
        campaign_name,
        ad_group_name,
        ad_type,
        account_snake_case AS account_name,
        account_descriptive_name,
        report_type,
        (campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
        dt_loaded
    FROM 
        datalake_google_ads_clean.ads_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
)
SELECT 
    clean_table_common.*,
    NOW() AS ts_load
FROM 
    clean_table_common
    LEFT JOIN dw_google_ads.dim_google_ad st_dim
        ON clean_table_common.sk_ad = st_dim.sk_ad
WHERE 
    st_dim.sk_ad IS NULL