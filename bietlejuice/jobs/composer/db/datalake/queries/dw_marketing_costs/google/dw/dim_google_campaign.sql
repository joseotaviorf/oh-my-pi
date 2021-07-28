WITH clean_table_common AS (
    SELECT DISTINCT
        SHA2(CONCAT(id_external_customer, id_campaign, campaign_name, device), 256) AS sk_campaign,
        id_external_customer,
        id_campaign,
        campaign_name,
        labels,
        account_snake_case AS account_name,
        account_descriptive_name,
        report_type,
        (campaign_name LIKE 'ZEBRA%') AS is_test_campaign,
        dt_loaded
    FROM 
        datalake_google_ads_clean.campaigns_performance_report
    WHERE
        dt_loaded = DATE('{year}-{month}-{day}')
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