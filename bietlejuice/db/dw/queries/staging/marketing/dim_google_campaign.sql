WITH clean_table_common as (
    SELECT
        MIN(id) as sk_campaign,
        account_id,
        campaign_id,
        campaign_name,
        acc as account_name,
        labels
    FROM staging.marketing_google_campaigns
    group by 2,3,4,5,6
)
SELECT clean_table_common.*,
		getdate() as ts_load
FROM clean_table_common
left join staging.dim_google_campaign st_dim
    on clean_table_common.campaign_id = st_dim.campaign_id
        and clean_table_common.account_name = st_dim.account_name
        and clean_table_common.campaign_name = st_dim.campaign_name
where st_dim.sk_campaign is null