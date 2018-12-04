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
        date
    FROM staging.marketing_google_keywords
    WHERE device = 'Computers'
    GROUP BY 1,2,3,4,5,6,10
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
        date
    FROM staging.marketing_google_keywords
    WHERE device = 'Mobile devices with full browsers'
    GROUP BY 1,2,3,4,5,6,10
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
        date
    FROM staging.marketing_google_keywords
    WHERE device = 'Tablets with full browsers'
    GROUP BY 1,2,3,4,5,6,10
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
        (COALESCE(mobile_devices_keywords.total_cost, 0) + COALESCE(tablet_devices_keywords.total_cost, 0) + COALESCE(computer_devices_keywords.total_cost, 0)) as total_cost,
        (COALESCE(mobile_devices_keywords.impressions, 0) + COALESCE(tablet_devices_keywords.impressions, 0) + COALESCE(computer_devices_keywords.impressions, 0)) as impressions,
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
        cte_keywords.account_id,
        cte_keywords.campaign_id,
        cte_keywords.adgroup_id,
        cte_keywords.mobile_clicks,
        cte_keywords.tablet_clicks,
        cte_keywords.computer_clicks,
        cte_keywords.total_clicks,
        cte_keywords.total_cost,
        cte_keywords.impressions,
        getdate() as ts_load
    from cte_keywords
    left join staging.dim_google_keyword dim
    on dim.keyword_id = cte_keywords.keyword_id
        and dim.account_name = cte_keywords.acc
        and dim.adgroup_name = cte_keywords.adgroup_name
        and dim.campaign_name = cte_keywords.campaign_name
        and dim.match_type = cte_keywords.match_type
)