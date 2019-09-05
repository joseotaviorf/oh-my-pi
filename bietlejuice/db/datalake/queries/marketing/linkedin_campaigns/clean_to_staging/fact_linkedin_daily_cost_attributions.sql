select * from (
    select
        id_ad as sk_ad,
        id_campaign as sk_campaign,
        id_ad,
        ad_name,
        cast(date_format(cast(dt_created as date), '%Y%m%d') as integer) as sk_date,
        total_spent,
        impressions,
        clicks,
        other_clicks,
        current_timestamp as ts_load
    from datalake_clean.marketing_linkedin_campaigns
)