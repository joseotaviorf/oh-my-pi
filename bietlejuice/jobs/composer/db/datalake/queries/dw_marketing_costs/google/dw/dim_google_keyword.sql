WITH clean_table_common AS (
    SELECT DISTINCT
        SHA2(CONCAT(id_external_customer, id_keyword, campaign_name, ad_group_name, device), 256) AS sk_keyword,
        id_keyword AS id_keyword,
        criteria AS keyword_name,
        campaign_name,
        ad_group_name,
        account_snake_case AS account_name,
        account_descriptive_name,
        match_type,
        report_type,
        (campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
        dt_loaded
    FROM 
        datalake_google_ads_clean.keywords_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
)
SELECT 
    clean_table_common.*,
    NOW() AS ts_load
FROM 
    clean_table_common
    LEFT JOIN dw_marketing_costs.dim_google_keyword st_dim
        ON clean_table_common.sk_keyword = st_dim.sk_keyword
WHERE 
    st_dim.sk_keyword IS NULL