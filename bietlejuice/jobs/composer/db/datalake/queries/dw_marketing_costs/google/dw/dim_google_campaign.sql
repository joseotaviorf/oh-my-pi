WITH clean_table_common AS (
    SELECT DISTINCT
        id AS sk_campaign,
        id_external_customer,
        id_campaign,
        campaign_name,
        acc AS account_name,
        labels,
        is_test_campaign,
        report_type,
        load_date
    FROM 
        datalake_marketing_costs.google_campaigns_performance_report
    WHERE
        load_date = DATE('{year}-{month}-{day}')
)
SELECT 
    clean_table_common.*,
	NOW() AS ts_load
FROM 
    clean_table_common
    LEFT JOIN dw_marketing_costs.dim_google_campaign st_dim
        ON clean_table_common.sk_campaign = st_dim.sk_campaign
WHERE 
    st_dim.sk_campaign IS NULL