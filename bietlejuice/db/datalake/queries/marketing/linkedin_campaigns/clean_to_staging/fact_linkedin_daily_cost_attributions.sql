select * from (
    select
        id_campaign as sk_campaign,
        id_account,
        cast(date_format(cast(dt_created as date), '%Y%m%d') as integer) as sk_date,
        impressions,
        clicks,
        ctr,
        cpc,
        current_timestamp as ts_load
     from datalake_clean.marketing_linkedin_campaigns
)