select * from (
    select
        id_creative as sk_creative,
        cam.id as sk_campaign,
        cgr.id as sk_campaign_group,
        cast(date_format(cast(stats.dt_created as date), '%Y%m%d') as integer) as sk_date,
        cost_in_local_currency as total_cost,
        card_clicks,
        card_impressions,
        clicks,
        comments,
        company_page_clicks,
        follows,
        impressions,
        likes,
        opens,
        reactions,
        shares,
        sends,
        text_url_clicks,
        current_timestamp as ts_load
    from datalake_clean.marketing_linkedin_creatives_stats stats
    join datalake_clean.marketing_linkedin_creatives ctv
        on ctv.id = stats.id_creative and ctv.acc = stats.acc and ctv.dt_created = stats.dt_created
    join datalake_clean.marketing_linkedin_campaigns cam
        on cam.id = ctv.id_campaign and cam.acc = ctv.acc and cam.dt_created = ctv.dt_created
    join datalake_clean.marketing_linkedin_campaign_groups cgr
        on cgr.id = cam.id_campaign_group and cgr.acc = cam.acc and cgr.dt_created = cam.dt_created
)
