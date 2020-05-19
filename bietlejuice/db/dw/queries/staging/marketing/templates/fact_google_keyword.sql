computer_devices_keywords as (
    SELECT keyword_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        date
    FROM staging.marketing_google_keywords
    WHERE device = 'Computers'
    GROUP BY 1,2,3,4,5,6,12
),
mobile_devices_keywords as (
    SELECT keyword_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        date
    FROM staging.marketing_google_keywords
    WHERE device = 'Mobile devices with full browsers'
    GROUP BY 1,2,3,4,5,6,12
),
tablet_devices_keywords as (
    SELECT keyword_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        date
    FROM staging.marketing_google_keywords
    WHERE device = 'Tablets with full browsers'
    GROUP BY 1,2,3,4,5,6,12
),
cte_keywords as (
    SELECT min(id) over (PARTITION BY google_table.keyword_id, google_table.account_id, google_table.campaign_id, google_table.adgroup_id) as id,
        cast(replace(google_table.date, '-', '') as integer) as sk_date,
        google_table.keyword_id::bigint,
        google_table.account_id,
        google_table.campaign_id,
        google_table.adgroup_id,
        google_table.account_name,
        google_table.campaign_name,
        google_table.adgroup_name,
        google_table.match_type,
        COALESCE(mobile_devices_keywords.total_clicks, 0) as mobile_clicks,
        COALESCE(tablet_devices_keywords.total_clicks, 0) as tablet_clicks,
        COALESCE(computer_devices_keywords.total_clicks, 0) as computer_clicks,
        (COALESCE(mobile_devices_keywords.total_clicks, 0) + COALESCE(tablet_devices_keywords.total_clicks, 0) + COALESCE(computer_devices_keywords.total_clicks, 0)) as total_clicks,
        (COALESCE(mobile_devices_keywords.total_cost, 0) + COALESCE(tablet_devices_keywords.total_cost, 0)) as mobile_cost,
        COALESCE(computer_devices_keywords.total_cost, 0) as desktop_cost,
        (COALESCE(mobile_devices_keywords.total_cost, 0) + COALESCE(tablet_devices_keywords.total_cost, 0) + COALESCE(computer_devices_keywords.total_cost, 0)) as total_cost,
        COALESCE(mobile_devices_keywords.impressions, 0)  as mobile_impressions,
        COALESCE(tablet_devices_keywords.impressions, 0)  as tablet_impressions,
        COALESCE(computer_devices_keywords.impressions, 0)  as desktop_impressions,
        (COALESCE(mobile_devices_keywords.impressions, 0) + COALESCE(tablet_devices_keywords.impressions, 0) + COALESCE(computer_devices_keywords.impressions, 0)) as impressions,
        COALESCE(computer_devices_keywords.search_impression_share, 0)             as desktop_search_impression_share,
        COALESCE(mobile_devices_keywords.search_impression_share, 0)               as mobile_search_impression_share,
        COALESCE(tablet_devices_keywords.search_impression_share, 0)               as tablet_search_impression_share,
        COALESCE(computer_devices_keywords.absolute_top_impression_percentage, 0)  as desktop_absolute_top_impression_percentage,
        COALESCE(mobile_devices_keywords.absolute_top_impression_percentage, 0)    as mobile_absolute_top_impression_percentage,
        COALESCE(tablet_devices_keywords.absolute_top_impression_percentage, 0)    as tablet_absolute_top_impression_percentage,
        google_table.acc
FROM staging.marketing_google_keywords google_table
LEFT JOIN computer_devices_keywords
    ON computer_devices_keywords.account_id = google_table.account_id
        AND computer_devices_keywords.campaign_id = google_table.campaign_id
        AND computer_devices_keywords.adgroup_id = google_table.adgroup_id
        AND computer_devices_keywords.keyword_id = google_table.keyword_id
        AND computer_devices_keywords.date = google_table.date
LEFT JOIN mobile_devices_keywords
    ON mobile_devices_keywords.account_id = google_table.account_id
        AND mobile_devices_keywords.campaign_id = google_table.campaign_id
        AND mobile_devices_keywords.adgroup_id = google_table.adgroup_id
        AND mobile_devices_keywords.keyword_id = google_table.keyword_id
        AND mobile_devices_keywords.date = google_table.date
LEFT JOIN tablet_devices_keywords
    ON tablet_devices_keywords.account_id = google_table.account_id
        AND tablet_devices_keywords.campaign_id = google_table.campaign_id
        AND tablet_devices_keywords.adgroup_id = google_table.adgroup_id
        AND tablet_devices_keywords.keyword_id = google_table.keyword_id
        AND tablet_devices_keywords.date = google_table.date
),
final_cte_keywords as (
    SELECT distinct
        cte_keywords.sk_date,
        coalesce(dim.sk_keyword, cte_keywords.id) as sk_keyword,
        cte_keywords.keyword_id,
        -1 as sk_ad,
        -1 as ad_id,
        -1 as sk_campaign,
        cte_keywords.account_id,
        cte_keywords.campaign_id,
        cte_keywords.adgroup_id,
        cte_keywords.mobile_clicks,
        cte_keywords.tablet_clicks,
        cte_keywords.computer_clicks,
        cte_keywords.total_clicks,
        cte_keywords.mobile_cost,
        cte_keywords.desktop_cost,
        cte_keywords.total_cost,
        cte_keywords.mobile_impressions,
        cte_keywords.tablet_impressions,
        cte_keywords.desktop_impressions,
        cte_keywords.impressions,
        -- Search Impression Share is the impressions we've received on the Search Network divided by the
        -- estimated number of impressions we were eligible to receive. Value ranging from 0 to 100.
        cte_keywords.desktop_search_impression_share,
        cte_keywords.mobile_search_impression_share,
        cte_keywords.tablet_search_impression_share,
        -- Absolute Top Impression Perc. is the percent of our ad impressions that are shown as the very
        -- first ad above the organic search results. Value ranging from 0 to 1.
        cte_keywords.desktop_absolute_top_impression_percentage,
        cte_keywords.mobile_absolute_top_impression_percentage,
        cte_keywords.tablet_absolute_top_impression_percentage,
        getdate() as ts_load
    from cte_keywords
    left join staging.dim_google_keyword dim
    on dim.keyword_id = cte_keywords.keyword_id
        and dim.account_name = cte_keywords.acc
        and dim.adgroup_name = cte_keywords.adgroup_name
        and dim.campaign_name = cte_keywords.campaign_name
        and dim.match_type = cte_keywords.match_type
)