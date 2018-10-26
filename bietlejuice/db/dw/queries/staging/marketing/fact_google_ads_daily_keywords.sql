WITH computer_devices as (
    SELECT keyword_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        criteria,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        date
    FROM staging.marketing_google_ads_keywords
    WHERE device = 'Computers'
    GROUP BY 1,2,3,4,5,6,7,11
),
mobile_devices as (
    SELECT keyword_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        criteria,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        date
    FROM staging.marketing_google_ads_keywords
    WHERE device = 'Mobile devices with full browsers'
    GROUP BY 1,2,3,4,5,6,7,11
),
tablet_devices as (
    SELECT keyword_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        criteria,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        SUM(COALESCE(cast(cost as float), 0)) / 1000000 as total_cost,
        MAX(COALESCE(cast(impressions as integer), 0)) as impressions,
        date
    FROM staging.marketing_google_ads_keywords
    WHERE device = 'Tablets with full browsers'
    GROUP BY 1,2,3,4,5,6,7,11
),
fact as (
    SELECT min(id) over (PARTITION BY keywords.keyword_id, keywords.account_id, keywords.campaign_id, keywords.adgroup_id) as id,
        cast(replace(keywords.date, '-', '') as integer) as sk_date,
        keywords.keyword_id,
        keywords.account_id,
        keywords.campaign_id,
        keywords.adgroup_id,
        keywords.account_name,
        keywords.campaign_name,
        keywords.adgroup_name,
        keywords.match_type,
        COALESCE(mobile_devices.total_clicks, 0) as mobile_clicks,
        COALESCE(tablet_devices.total_clicks, 0) as tablet_clicks,
        COALESCE(computer_devices.total_clicks, 0) as computer_clicks,
        (COALESCE(mobile_devices.total_clicks, 0) + COALESCE(tablet_devices.total_clicks, 0) + COALESCE(computer_devices.total_clicks, 0)) as total_clicks,
        (COALESCE(mobile_devices.total_cost, 0) + COALESCE(tablet_devices.total_cost, 0) + COALESCE(computer_devices.total_cost, 0)) as total_cost,
        (COALESCE(mobile_devices.impressions, 0) + COALESCE(tablet_devices.impressions, 0) + COALESCE(computer_devices.impressions, 0)) as impressions,
        keywords.dt_created,
        keywords.acc
FROM staging.marketing_google_ads_keywords keywords
LEFT JOIN computer_devices
    ON computer_devices.account_id = keywords.account_id
        AND computer_devices.campaign_id = keywords.campaign_id
        AND computer_devices.adgroup_id = keywords.adgroup_id
        AND computer_devices.keyword_id = keywords.keyword_id
        AND computer_devices.date = keywords.date
LEFT JOIN mobile_devices
    ON mobile_devices.account_id = keywords.account_id
        AND mobile_devices.campaign_id = keywords.campaign_id
        AND mobile_devices.adgroup_id = keywords.adgroup_id
        AND mobile_devices.keyword_id = keywords.keyword_id
        AND mobile_devices.date = keywords.date
LEFT JOIN tablet_devices
    ON tablet_devices.account_id = keywords.account_id
        AND tablet_devices.campaign_id = keywords.campaign_id
        AND tablet_devices.adgroup_id = keywords.adgroup_id
        AND tablet_devices.keyword_id = keywords.keyword_id
        AND tablet_devices.date = keywords.date
)
SELECT distinct
    coalesce(dim.sk_keyword, fact.id) as sk_keyword,
    fact.sk_date,
    fact.keyword_id,
    fact.account_id,
    fact.campaign_id,
    fact.adgroup_id,
    fact.mobile_clicks,
    fact.tablet_clicks,
    fact.computer_clicks,
    fact.total_clicks,
    fact.total_cost,
    fact.impressions,
    fact.dt_created
from fact
left join staging.dim_google_ads_keyword dim
on dim.keyword_id = fact.keyword_id
    and dim.account_name = fact.acc
    and dim.adgroup_name = fact.adgroup_name
    and dim.campaign_name = fact.campaign_name
    and dim.match_type = fact.match_type