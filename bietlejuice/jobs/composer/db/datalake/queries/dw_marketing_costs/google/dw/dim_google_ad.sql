WITH clean_table_common AS (
    SELECT DISTINCT
        id AS sk_ad,
        id_ad,
        acc AS account_name,
        campaign_name,
        ad_group_name,
        account_descriptive_name,
        ad_type,
        is_test_campaign,
        report_type,
        load_date
    FROM 
        datalake_marketing_costs.google_ads_performance_report
    WHERE
        load_date = DATE('{year}-{month}-{day}')
)
SELECT 
    clean_table_common.*,
    NOW() AS ts_load
FROM 
    clean_table_common
    LEFT JOIN dw_marketing_costs.dim_google_ad st_dim
        ON clean_table_common.sk_ad = st_dim.sk_ad
WHERE 
    st_dim.sk_ad IS NULL