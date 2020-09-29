WITH clean_table_common as (
    SELECT
        first(id) as sk_keyword,
        id_keyword as id_keyword,
        criteria as keyword_name,
        acc as account_name,
        campaign_name,
        ad_group_name,
        match_type,
        is_test_campaign,
        report_type,
        load_date
    FROM 
        datalake_marketing_costs.google_keywords_performance_report
    WHERE
        dt_load = '{year}-{month}-{day}'
    group by 2,3,4,5,6,7,8,9
)
SELECT 
    clean_table_common.*,
    now() as ts_load
FROM 
    clean_table_common
left join dw_marketing_costs_staging.dim_google_keyword st_dim
    on clean_table_common.sk_keyword = st_dim.sk_keyword
where st_dim.sk_keyword is null