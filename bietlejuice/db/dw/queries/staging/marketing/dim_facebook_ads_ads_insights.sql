WITH clean_table_common as (
    SELECT
        MIN(id) as sk_ad,
        ad_id,
        ad_name,
        adset_name,
        campaign_name,
        acc as account_name,
        dt_created,
        getdate() as ts_load
    FROM staging.marketing_facebook_ads_ads_insights {where_clause}
    group by 2,3,4,5,6,7,8
)
SELECT clean_table_common.* FROM clean_table_common
LEFT JOIN staging.dim_facebook_ads_ads_insights stg_dim
    ON clean_table_common.sk_ad = stg_dim.sk_ad
        AND clean_table_common.account_name = stg_dim.account_name
        AND clean_table_common.adset_name = stg_dim.adset_name
        AND clean_table_common.campaign_name = stg_dim.campaign_name
WHERE stg_dim.sk_ad IS NULL