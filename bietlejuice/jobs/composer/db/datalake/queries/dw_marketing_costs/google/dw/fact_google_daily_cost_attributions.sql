-- ADS START
WITH
    computer_devices_ads as (
    select 
        id_ad,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        sum(coalesce(cast(clicks as integer), 0)) as total_clicks,
        sum(coalesce(cast(cost as float), 0)) / 1000000 as total_cost,
        sum(coalesce(cast(impressions as integer), 0)) as impressions,
        max(coalesce(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    from datalake_marketing_costs.google_ads_performance_report
    where device = 'Computers'
        and load_date = date('{year}-{month}-{day}')
    group by 1,2,3,4,5,6,11,12
),
mobile_devices_ads as (
    select 
        id_ad,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        sum(coalesce(cast(clicks as integer), 0)) as total_clicks,
        sum(coalesce(cast(cost as float), 0)) / 1000000 as total_cost,
        sum(coalesce(cast(impressions as integer), 0)) as impressions,
        max(coalesce(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    from datalake_marketing_costs.google_ads_performance_report
    where device = 'Mobile devices with full browsers'
        and load_date = date('{year}-{month}-{day}')
    group by 1,2,3,4,5,6,11,12
),
tablet_devices_ads as (
    select 
        id_ad,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        sum(coalesce(cast(clicks as integer), 0)) as total_clicks,
        sum(coalesce(cast(cost as float), 0)) / 1000000 as total_cost,
        sum(coalesce(cast(impressions as integer), 0)) as impressions,
        max(coalesce(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    from datalake_marketing_costs.google_ads_performance_report
    where device = 'Tablets with full browsers'
        and load_date = date('{year}-{month}-{day}')
    group by 1,2,3,4,5,6,11,12
),
cte_ads as (
    select 
        min(id) over (partition by google_table.id_ad, google_table.id_external_customer, google_table.id_campaign, google_table.id_ad_group) as id,
        cast(replace(google_table.dt_load, '-', '') as integer) as sk_date,
        bigint(google_table.id_ad),
        google_table.id_external_customer,
        google_table.id_campaign,
        google_table.id_ad_group,
        google_table.account_name,
        google_table.campaign_name,
        google_table.ad_group_name,
        google_table.ad_type,
        COALESCE(mobile_devices_ads.total_clicks, 0) as mobile_clicks,
        COALESCE(tablet_devices_ads.total_clicks, 0) as tablet_clicks,
        COALESCE(computer_devices_ads.total_clicks, 0) as computer_clicks,
        (COALESCE(mobile_devices_ads.total_clicks, 0) + COALESCE(tablet_devices_ads.total_clicks, 0) + COALESCE(computer_devices_ads.total_clicks, 0)) as total_clicks,
        (COALESCE(mobile_devices_ads.total_cost, 0) + COALESCE(tablet_devices_ads.total_cost, 0)) as mobile_cost,
        COALESCE(computer_devices_ads.total_cost, 0) as desktop_cost,
        (COALESCE(mobile_devices_ads.total_cost, 0) + COALESCE(tablet_devices_ads.total_cost, 0) + COALESCE(computer_devices_ads.total_cost, 0)) as total_cost,
        COALESCE(mobile_devices_ads.impressions, 0) as mobile_impressions,
        COALESCE(tablet_devices_ads.impressions, 0) as tablet_impressions,
        COALESCE(computer_devices_ads.impressions, 0) as desktop_impressions,
        (COALESCE(mobile_devices_ads.impressions, 0) + COALESCE(tablet_devices_ads.impressions, 0) + COALESCE(computer_devices_ads.impressions, 0)) as impressions,
        COALESCE(computer_devices_ads.absolute_top_impression_percentage, 0)    as desktop_absolute_top_impression_percentage,
        COALESCE(mobile_devices_ads.absolute_top_impression_percentage, 0)      as mobile_absolute_top_impression_percentage,
        COALESCE(tablet_devices_ads.absolute_top_impression_percentage, 0)      as tablet_absolute_top_impression_percentage,
        google_table.acc,
        google_table.load_date
FROM datalake_marketing_costs.google_ads_performance_report google_table
LEFT JOIN computer_devices_ads
    ON computer_devices_ads.id_external_customer = google_table.id_external_customer
        AND computer_devices_ads.id_campaign = google_table.id_campaign
        AND computer_devices_ads.id_ad_group = google_table.id_ad_group
        AND computer_devices_ads.id_ad = google_table.id_ad
        AND computer_devices_ads.dt_load = google_table.dt_load
LEFT JOIN mobile_devices_ads
    ON mobile_devices_ads.id_external_customer = google_table.id_external_customer
        AND mobile_devices_ads.id_campaign = google_table.id_campaign
        AND mobile_devices_ads.id_ad_group = google_table.id_ad_group
        AND mobile_devices_ads.id_ad = google_table.id_ad
        AND mobile_devices_ads.dt_load = google_table.dt_load
LEFT JOIN tablet_devices_ads
    ON tablet_devices_ads.id_external_customer = google_table.id_external_customer
        AND tablet_devices_ads.id_campaign = google_table.id_campaign
        AND tablet_devices_ads.id_ad_group = google_table.id_ad_group
        AND tablet_devices_ads.id_ad = google_table.id_ad
        AND tablet_devices_ads.dt_load = google_table.dt_load
WHERE
    google_table.load_date = date('{year}-{month}-{day}')
),
final_cte_ads as (
    select distinct
        cte_ads.sk_date,
        -1 as sk_keyword,
        coalesce(dim.sk_ad, cte_ads.id) as sk_ad,
        -1 as sk_campaign,
        cte_ads.id_ad,
        -1 as keyword_id,
        cte_ads.id_external_customer,
        cte_ads.id_campaign,
        cte_ads.id_ad_group,
        cte_ads.mobile_clicks,
        cte_ads.tablet_clicks,
        cte_ads.computer_clicks,
        cte_ads.total_clicks,
        cte_ads.mobile_cost,
        cte_ads.desktop_cost,
        cte_ads.total_cost,
        cte_ads.mobile_impressions,
        cte_ads.tablet_impressions,
        cte_ads.desktop_impressions,
        cte_ads.impressions,
        -- Search Impression Share is the impressions we've received on the Search Network divided by the
        -- estimated number of impressions we were eligible to receive. Value ranging from 0 to 100.
        cast(0 as float) as desktop_search_impression_share,
        cast(0 as float) as mobile_search_impression_share,
        cast(0 as float) as tablet_search_impression_share,
        -- Absolute Top Impression Perc. is the percent of our ad impressions that are shown as the very
        -- first ad above the organic search results. Value ranging from 0 to 1.
        cte_ads.desktop_absolute_top_impression_percentage,
        cte_ads.mobile_absolute_top_impression_percentage,
        cte_ads.tablet_absolute_top_impression_percentage,
        now() as ts_load,
        cte_ads.load_date
    from cte_ads
    left join dw_marketing_costs_staging.dim_google_ad dim
    on dim.id_ad = cte_ads.id_ad
        and dim.account_name = cte_ads.acc
        and dim.ad_group_name = cte_ads.ad_group_name
        and dim.campaign_name = cte_ads.campaign_name
        and dim.ad_type = cte_ads.ad_type
),

-- ADS END
-- KEYWORDS START

computer_devices_keywords as (
    SELECT id_keyword,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    FROM datalake_marketing_costs.google_keywords_performance_report
    WHERE device = 'Computers'
        AND load_date = date('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,5,6,12,13
),
mobile_devices_keywords as (
    SELECT id_keyword,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    FROM datalake_marketing_costs.google_keywords_performance_report
    WHERE device = 'Mobile devices with full browsers'
        AND load_date = date('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,5,6,12,13
),
tablet_devices_keywords as (
    SELECT id_keyword,
        id_campaign,
        id_external_customer,
        id_ad_group,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    FROM datalake_marketing_costs.google_keywords_performance_report
    WHERE device = 'Tablets with full browsers'
        AND load_date = date('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,5,6,12,13
),
cte_keywords as (
    SELECT min(id) over (PARTITION BY google_table.id_keyword, google_table.id_external_customer, google_table.id_campaign, google_table.id_ad_group) as id,
        cast(replace(google_table.dt_load, '-', '') as integer) as sk_date,
        google_table.id_keyword,
        google_table.id_external_customer,
        google_table.id_campaign,
        google_table.id_ad_group,
        google_table.account_descriptive_name,
        google_table.campaign_name,
        google_table.ad_group_name,
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
        google_table.acc,
        google_table.load_date
FROM datalake_marketing_costs.google_keywords_performance_report google_table
LEFT JOIN computer_devices_keywords
    ON computer_devices_keywords.id_external_customer = google_table.id_external_customer
        AND computer_devices_keywords.id_campaign = google_table.id_campaign
        AND computer_devices_keywords.id_ad_group = google_table.id_ad_group
        AND computer_devices_keywords.id_keyword = google_table.id_keyword
        AND computer_devices_keywords.dt_load = google_table.dt_load
LEFT JOIN mobile_devices_keywords
    ON mobile_devices_keywords.id_external_customer = google_table.id_external_customer
        AND mobile_devices_keywords.id_campaign = google_table.id_campaign
        AND mobile_devices_keywords.id_ad_group = google_table.id_ad_group
        AND mobile_devices_keywords.id_keyword = google_table.id_keyword
        AND mobile_devices_keywords.dt_load = google_table.dt_load
LEFT JOIN tablet_devices_keywords
    ON tablet_devices_keywords.id_external_customer = google_table.id_external_customer
        AND tablet_devices_keywords.id_campaign = google_table.id_campaign
        AND tablet_devices_keywords.id_ad_group = google_table.id_ad_group
        AND tablet_devices_keywords.id_keyword = google_table.id_keyword
        AND tablet_devices_keywords.dt_load = google_table.dt_load
WHERE google_table.load_date = date('{year}-{month}-{day}')
),
final_cte_keywords as (
    SELECT distinct
        cte_keywords.sk_date,
        coalesce(dim.sk_keyword, cte_keywords.id) as sk_keyword,
        -1 as sk_ad,
        -1 as sk_campaign,
        -1 as id_ad,
        cte_keywords.id_keyword,
        cte_keywords.id_external_customer,
        cte_keywords.id_campaign,
        cte_keywords.id_ad_group,
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
        now() as ts_load,
        cte_keywords.load_date
    from cte_keywords
    left join dw_marketing_costs_staging.dim_google_keyword dim
    on dim.id_keyword = cte_keywords.id_keyword
        and dim.account_name = cte_keywords.acc
        and dim.ad_group_name = cte_keywords.ad_group_name
        and dim.campaign_name = cte_keywords.campaign_name
        and dim.match_type = cte_keywords.match_type
),

-- KEYWORDS END
-- CAMPAIGNS START

computer_devices_campaigns as (
    SELECT 
        id_campaign,
        id_external_customer,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    FROM datalake_marketing_costs.google_campaigns_performance_report
    WHERE device = 'Computers'
        AND load_date = date('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,10,11
),
mobile_devices_campaigns as (
    SELECT id_campaign,
        id_external_customer,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    FROM datalake_marketing_costs.google_campaigns_performance_report
    WHERE device = 'Mobile devices with full browsers'
        AND load_date = date('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,10,11
),
tablet_devices_campaigns as (
    SELECT id_campaign,
        id_external_customer,
        campaign_name,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        MAX(COALESCE(cast(search_impression_share as float), 0))            as search_impression_share,
        MAX(COALESCE(cast(absolute_top_impression_percentage as float), 0)) as absolute_top_impression_percentage,
        dt_load,
        load_date
    FROM datalake_marketing_costs.google_campaigns_performance_report
    WHERE device = 'Tablets with full browsers'
        AND load_date = date('{year}-{month}-{day}')
    GROUP BY 1,2,3,4,10,11
),
cte_campaigns as (
    SELECT min(id) over (PARTITION BY google_table.id_campaign, google_table.id_external_customer) as id,
        cast(replace(google_table.dt_load, '-', '') as integer) as sk_date,
        google_table.id_external_customer,
        google_table.id_campaign,
        google_table.account_descriptive_name,
        google_table.campaign_name,
        COALESCE(mobile_devices_campaigns.total_clicks, 0) as mobile_clicks,
        COALESCE(tablet_devices_campaigns.total_clicks, 0) as tablet_clicks,
        COALESCE(computer_devices_campaigns.total_clicks, 0) as computer_clicks,
        (COALESCE(mobile_devices_campaigns.total_clicks, 0) + COALESCE(tablet_devices_campaigns.total_clicks, 0) + COALESCE(computer_devices_campaigns.total_clicks, 0)) as total_clicks,
        (COALESCE(mobile_devices_campaigns.total_cost, 0) + COALESCE(tablet_devices_campaigns.total_cost, 0)) as mobile_cost,
        COALESCE(computer_devices_campaigns.total_cost, 0) as desktop_cost,
        (COALESCE(mobile_devices_campaigns.total_cost, 0) + COALESCE(tablet_devices_campaigns.total_cost, 0) + COALESCE(computer_devices_campaigns.total_cost, 0)) as total_cost,
        COALESCE(mobile_devices_campaigns.impressions, 0) as mobile_impressions,
        COALESCE(tablet_devices_campaigns.impressions, 0) as tablet_impressions,
        COALESCE(computer_devices_campaigns.impressions, 0) as desktop_impressions,
        (COALESCE(mobile_devices_campaigns.impressions, 0) + COALESCE(tablet_devices_campaigns.impressions, 0) + COALESCE(computer_devices_campaigns.impressions, 0)) as impressions,
        COALESCE(computer_devices_campaigns.search_impression_share, 0)             as desktop_search_impression_share,
        COALESCE(mobile_devices_campaigns.search_impression_share, 0)               as mobile_search_impression_share,
        COALESCE(tablet_devices_campaigns.search_impression_share, 0)               as tablet_search_impression_share,
        COALESCE(computer_devices_campaigns.absolute_top_impression_percentage, 0)  as desktop_absolute_top_impression_percentage,
        COALESCE(mobile_devices_campaigns.absolute_top_impression_percentage, 0)    as mobile_absolute_top_impression_percentage,
        COALESCE(tablet_devices_campaigns.absolute_top_impression_percentage, 0)    as tablet_absolute_top_impression_percentage,
        google_table.acc,
        google_table.load_date
FROM datalake_marketing_costs.google_campaigns_performance_report google_table
LEFT JOIN computer_devices_campaigns
    ON computer_devices_campaigns.id_external_customer = google_table.id_external_customer
        AND computer_devices_campaigns.id_campaign = google_table.id_campaign
        AND computer_devices_campaigns.dt_load = google_table.dt_load
LEFT JOIN mobile_devices_campaigns
    ON mobile_devices_campaigns.id_external_customer = google_table.id_external_customer
        AND mobile_devices_campaigns.id_campaign = google_table.id_campaign
        AND mobile_devices_campaigns.dt_load = google_table.dt_load
LEFT JOIN tablet_devices_campaigns
    ON tablet_devices_campaigns.id_external_customer = google_table.id_external_customer
        AND tablet_devices_campaigns.id_campaign = google_table.id_campaign
        AND tablet_devices_campaigns.dt_load = google_table.dt_load
WHERE
    google_table.load_date = date('{year}-{month}-{day}')
),
final_cte_campaigns as (
    SELECT distinct
        cte_campaigns.sk_date,
        -1 as sk_keyword,
        -1 as sk_ad,
        coalesce(dim.sk_campaign, cte_campaigns.id) as sk_campaign,
        -1 as id_ad,
        -1 as keyword_id,
        cte_campaigns.id_external_customer,
        cte_campaigns.id_campaign,
        'null' as adgroup_id,
        cte_campaigns.mobile_clicks,
        cte_campaigns.tablet_clicks,
        cte_campaigns.computer_clicks,
        cte_campaigns.total_clicks,
        cte_campaigns.mobile_cost,
        cte_campaigns.desktop_cost,
        cte_campaigns.total_cost,
        cte_campaigns.mobile_impressions,
        cte_campaigns.tablet_impressions,
        cte_campaigns.desktop_impressions,
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
        now() as ts_load,
        cte_campaigns.load_date
    from cte_campaigns
    left join dw_marketing_costs_staging.dim_google_campaign dim
    on dim.id_campaign = cte_campaigns.id_campaign
        and dim.account_name = cte_campaigns.acc
        and dim.campaign_name = cte_campaigns.campaign_name
)
-- CAMPAIGNS END

SELECT * FROM final_cte_keywords
union all
SELECT * FROM final_cte_ads
union all
SELECT * FROM final_cte_campaigns