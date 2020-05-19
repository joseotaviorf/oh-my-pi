computer_devices_campaigns as (
    SELECT campaign_id,
        account_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        date
    FROM staging.marketing_google_campaigns
    WHERE device = 'Computers'
    GROUP BY 1,2,3,4,10
),
mobile_devices_campaigns as (
    SELECT campaign_id,
        account_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        date
    FROM staging.marketing_google_campaigns
    WHERE device = 'Mobile devices with full browsers'
    GROUP BY 1,2,3,4,10
),
tablet_devices_campaigns as (
    SELECT campaign_id,
        account_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        date
    FROM staging.marketing_google_campaigns
    WHERE device = 'Tablets with full browsers'
    GROUP BY 1,2,3,4,10
),
cte_campaigns as (
    SELECT min(id) over (PARTITION BY google_table.campaign_id, google_table.account_id) as id,
        cast(replace(google_table.date, '-', '') as integer) as sk_date,
        google_table.account_id,
        google_table.campaign_id,
        google_table.account_name,
        google_table.campaign_name,
        COALESCE(mobile_devices_campaigns.total_clicks, 0) as mobile_clicks,
        COALESCE(tablet_devices_campaigns.total_clicks, 0) as tablet_clicks,
        COALESCE(computer_devices_campaigns.total_clicks, 0) as computer_clicks,
        (COALESCE(mobile_devices_campaigns.total_clicks, 0) + COALESCE(tablet_devices_campaigns.total_clicks, 0) + COALESCE(computer_devices_campaigns.total_clicks, 0)) as total_clicks,
        (COALESCE(mobile_devices_campaigns.total_cost, 0) + COALESCE(tablet_devices_campaigns.total_cost, 0)) as mobile_cost,
        COALESCE(computer_devices_campaigns.total_cost, 0) as desktop_cost,
        (COALESCE(mobile_devices_campaigns.total_cost, 0) + COALESCE(tablet_devices_campaigns.total_cost, 0) + COALESCE(computer_devices_campaigns.total_cost, 0)) as total_cost,
        (COALESCE(mobile_devices_campaigns.impressions, 0) + COALESCE(tablet_devices_campaigns.impressions, 0) + COALESCE(computer_devices_campaigns.impressions, 0)) as impressions,
        COALESCE(computer_devices_campaigns.search_impression_share, 0)             as desktop_search_impression_share,
        COALESCE(mobile_devices_campaigns.search_impression_share, 0)               as mobile_search_impression_share,
        COALESCE(tablet_devices_campaigns.search_impression_share, 0)               as tablet_search_impression_share,
        COALESCE(computer_devices_campaigns.absolute_top_impression_percentage, 0)  as desktop_absolute_top_impression_percentage,
        COALESCE(mobile_devices_campaigns.absolute_top_impression_percentage, 0)    as mobile_absolute_top_impression_percentage,
        COALESCE(tablet_devices_campaigns.absolute_top_impression_percentage, 0)    as tablet_absolute_top_impression_percentage,
        google_table.acc
FROM staging.marketing_google_campaigns google_table
LEFT JOIN computer_devices_campaigns
    ON computer_devices_campaigns.account_id = google_table.account_id
        AND computer_devices_campaigns.campaign_id = google_table.campaign_id
        AND computer_devices_campaigns.date = google_table.date
LEFT JOIN mobile_devices_campaigns
    ON mobile_devices_campaigns.account_id = google_table.account_id
        AND mobile_devices_campaigns.campaign_id = google_table.campaign_id
        AND mobile_devices_campaigns.date = google_table.date
LEFT JOIN tablet_devices_campaigns
    ON tablet_devices_campaigns.account_id = google_table.account_id
        AND tablet_devices_campaigns.campaign_id = google_table.campaign_id
        AND tablet_devices_campaigns.date = google_table.date
),
final_cte_campaigns as (
    SELECT distinct
        cte_campaigns.sk_date,
        -1 as sk_keyword,
        -1 as keyword_id,
        -1 as sk_ad,
        -1 as ad_id,
        coalesce(dim.sk_campaign, cte_campaigns.id) as sk_campaign,
        cte_campaigns.account_id,
        cte_campaigns.campaign_id,
        'null' as adgroup_id,
        cte_campaigns.mobile_clicks,
        cte_campaigns.tablet_clicks,
        cte_campaigns.computer_clicks,
        cte_campaigns.total_clicks,
        cte_campaigns.mobile_cost,
        cte_campaigns.desktop_cost,
        cte_campaigns.total_cost,
        cte_campaigns.impressions,
        -- Search Impression Share is the impressions we've received on the Search Network divided by the
        -- estimated number of impressions we were eligible to receive. Value ranging from 0 to 100.
        cte_campaigns.desktop_search_impression_share,
        cte_campaigns.mobile_search_impression_share,
        cte_campaigns.tablet_search_impression_share,
        -- Absolute Top Impression Perc. is the percent of our ad impressions that are shown as the very
        -- first ad above the organic search results. Value ranging from 0 to 1.
        cte_campaigns.desktop_absolute_top_impression_percentage,
        cte_campaigns.mobile_absolute_top_impression_percentage,
        cte_campaigns.tablet_absolute_top_impression_percentage,
        getdate() as ts_load
    from cte_campaigns
    left join staging.dim_google_campaign dim
    on dim.campaign_id = cte_campaigns.campaign_id
        and dim.account_name = cte_campaigns.acc
        and dim.campaign_name = cte_campaigns.campaign_name
)