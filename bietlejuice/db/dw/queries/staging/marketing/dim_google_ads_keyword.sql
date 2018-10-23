WITH clean_table_common as (
    SELECT
        MIN(id) as sk_keyword,
        keyword_id as keyword_id,
        criteria as keyword_name,
        acc as account_name,
        campaign_name,
        adgroup_name,
        match_type,
        getdate() as ts_load
    FROM staging.marketing_google_ads_keywords {where_clause}
    group by 2,3,4,5,6,7
)
SELECT clean_table_common.* FROM clean_table_common
left join staging.dim_google_ads_keyword st_dim
    on clean_table_common.keyword_id = st_dim.keyword_id
        and clean_table_common.account_name = st_dim.account_name
        and clean_table_common.adgroup_name = st_dim.adgroup_name
        and clean_table_common.campaign_name = st_dim.campaign_name
        and clean_table_common.match_type = st_dim.match_type
where st_dim.sk_keyword is null