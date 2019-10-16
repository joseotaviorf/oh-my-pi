select
    sk_ad,
    sk_campaign,
    sk_date,
    total_spent,
    impressions,
    clicks,
    other_clicks,
    ts_load
from (
    select
        id_ad as sk_ad,
        id_campaign as sk_campaign,
        cast(date_format(cast(dt_created as date), '%Y%m%d') as integer) as sk_date,
        total_spent,
        impressions,
        clicks,
        other_clicks,
        current_timestamp as ts_load
    from datalake_clean.marketing_linkedin_campaigns
)