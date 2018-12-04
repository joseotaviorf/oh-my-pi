WITH clean_table_common as (
    SELECT
        MIN(id) as sk_ad,
        ad_id,
        acc as account_name,
        campaign_name,
        adgroup_name,
        image_creative_name,
        ad_type
    FROM staging.marketing_google_ads
    group by 2,3,4,5,6,7
)
SELECT clean_table_common.*,
		getdate() as ts_load
FROM clean_table_common
left join staging.dim_google_ad st_dim
    on clean_table_common.ad_id = st_dim.ad_id
        and clean_table_common.account_name = st_dim.account_name
        and clean_table_common.adgroup_name = st_dim.adgroup_name
        and clean_table_common.campaign_name = st_dim.campaign_name
        and clean_table_common.ad_type = st_dim.ad_type
where st_dim.sk_ad is null