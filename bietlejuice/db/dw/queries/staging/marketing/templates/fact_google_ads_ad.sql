computer_devices_ads as (
    SELECT ad_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        SUM(COALESCE(cast(impressions as integer), 0)) as impressions,
        date
    FROM staging.marketing_google_ads
    WHERE device = 'Computers'
    GROUP BY 1,2,3,4,5,6,10
),
mobile_devices_ads as (
    SELECT ad_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        SUM(COALESCE(cast(impressions as integer), 0)) as impressions,
        date
    FROM staging.marketing_google_ads
    WHERE device = 'Mobile devices with full browsers'
    GROUP BY 1,2,3,4,5,6,10
),
tablet_devices_ads as (
    SELECT ad_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        SUM(COALESCE(cast(impressions as integer), 0)) as impressions,
        date
    FROM staging.marketing_google_ads
    WHERE device = 'Tablets with full browsers'
    GROUP BY 1,2,3,4,5,6,10
),
cte_ads as (
    SELECT min(id) over (PARTITION BY google_table.ad_id, google_table.account_id, google_table.campaign_id, google_table.adgroup_id) as id,
        cast(replace(google_table.date, '-', '') as integer) as sk_date,
        google_table.ad_id::bigint,
        google_table.account_id,
        google_table.campaign_id,
        google_table.adgroup_id,
        google_table.account_name,
        google_table.campaign_name,
        google_table.adgroup_name,
        google_table.ad_type,
        COALESCE(mobile_devices_ads.total_clicks, 0) as mobile_clicks,
        COALESCE(tablet_devices_ads.total_clicks, 0) as tablet_clicks,
        COALESCE(computer_devices_ads.total_clicks, 0) as computer_clicks,
        (COALESCE(mobile_devices_ads.total_clicks, 0) + COALESCE(tablet_devices_ads.total_clicks, 0) + COALESCE(computer_devices_ads.total_clicks, 0)) as total_clicks,
        (COALESCE(mobile_devices_ads.total_cost, 0) + COALESCE(tablet_devices_ads.total_cost, 0) + COALESCE(computer_devices_ads.total_cost, 0)) as total_cost,
        (COALESCE(mobile_devices_ads.impressions, 0) + COALESCE(tablet_devices_ads.impressions, 0) + COALESCE(computer_devices_ads.impressions, 0)) as impressions,
        google_table.acc
FROM staging.marketing_google_ads google_table
LEFT JOIN computer_devices_ads
    ON computer_devices_ads.account_id = google_table.account_id
        AND computer_devices_ads.campaign_id = google_table.campaign_id
        AND computer_devices_ads.adgroup_id = google_table.adgroup_id
        AND computer_devices_ads.ad_id = google_table.ad_id
        AND computer_devices_ads.date = google_table.date
LEFT JOIN mobile_devices_ads
    ON mobile_devices_ads.account_id = google_table.account_id
        AND mobile_devices_ads.campaign_id = google_table.campaign_id
        AND mobile_devices_ads.adgroup_id = google_table.adgroup_id
        AND mobile_devices_ads.ad_id = google_table.ad_id
        AND mobile_devices_ads.date = google_table.date
LEFT JOIN tablet_devices_ads
    ON tablet_devices_ads.account_id = google_table.account_id
        AND tablet_devices_ads.campaign_id = google_table.campaign_id
        AND tablet_devices_ads.adgroup_id = google_table.adgroup_id
        AND tablet_devices_ads.ad_id = google_table.ad_id
        AND tablet_devices_ads.date = google_table.date
),
final_cte_ads as (
    SELECT distinct
        cte_ads.sk_date,
        -1 as sk_keyword,
        -1 as keyword_id,
        coalesce(dim.sk_ad, cte_ads.id) as sk_ad,
        cte_ads.ad_id,
        cte_ads.account_id,
        cte_ads.campaign_id,
        cte_ads.adgroup_id,
        cte_ads.mobile_clicks,
        cte_ads.tablet_clicks,
        cte_ads.computer_clicks,
        cte_ads.total_clicks,
        cte_ads.total_cost,
        cte_ads.impressions,
        getdate() as ts_load
    from cte_ads
    left join staging.dim_google_ad dim
    on dim.ad_id = cte_ads.ad_id
        and dim.account_name = cte_ads.acc
        and dim.adgroup_name = cte_ads.adgroup_name
        and dim.campaign_name = cte_ads.campaign_name
        and dim.ad_type = cte_ads.ad_type
)