WITH clean_table_common as (
    SELECT
        first(id) as sk_ad,
        id_ad,
        acc as account_name,
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
        load_date = date('{year}-{month}-{day}')
    group by 2,3,4,5,6,7,8,9,10
)
SELECT clean_table_common.*,
    now() as ts_load
FROM 
    clean_table_common
left join dw_marketing_costs_staging.dim_google_ad st_dim
    on clean_table_common.sk_ad = st_dim.sk_ad
where st_dim.sk_ad is null