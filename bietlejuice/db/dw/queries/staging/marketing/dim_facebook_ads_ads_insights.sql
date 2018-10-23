WITH clean_table_common as (
    SELECT
        MIN(id) as sk_ad,
        ad_id,
        ad_name,
        adset_name,
        campaign_name,
        account_name,
        getdate() as ts_load
    FROM staging.marketing_facebook_ads_ads_insights
    group by 2,3,4,5,6,7
)
SELECT clean_table_common.* FROM clean_table_common
LEFT JOIN staging.dim_facebook_ads_ads_insight stg_dim
ON clean_table_common.keyword_id = stg_dim.keyword_id
AND clean_table_common.account_name = stg_dim.account_name
AND clean_table_common.adgroup_name = stg_dim.adgroup_name
AND clean_table_common.campaign_name = stg_dim.campaign_name
WHERE stg_dim.sk_keyword IS NULL