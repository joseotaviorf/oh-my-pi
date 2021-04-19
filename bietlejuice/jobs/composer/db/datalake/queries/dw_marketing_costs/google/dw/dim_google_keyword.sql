WITH clean_table_common AS (
    SELECT DISTINCT
        id AS sk_keyword,
        id_keyword AS id_keyword,
        criteria AS keyword_name,
        acc AS account_name,
        campaign_name,
        ad_group_name,
        match_type,
        is_test_campaign,
        report_type,
        load_date
    FROM 
        datalake_marketing_costs.google_keywords_performance_report
    WHERE
        load_date = DATE('{year}-{month}-{day}')
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