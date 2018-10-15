WITH computer_devices as (
    SELECT keyword_id,
        campaign_id,
        account_id,
        adgroup_id,
        campaign_name,
        criteria,
        device,
        SUM(COALESCE(cast(clicks as integer), 0)) as total_clicks,
        date
    FROM stitch.clean_keywords
    WHERE device = 'Computers'
    GROUP BY 1,2,3,4,5,6,7,9
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
        date
    FROM stitch.clean_keywords
    WHERE device = 'Mobile devices with full browsers'
    GROUP BY 1,2,3,4,5,6,7,9
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
        date
    FROM stitch.clean_keywords
    WHERE device = 'Tablets with full browsers'
    GROUP BY 1,2,3,4,5,6,7,9
),
keywords as (
    SELECT keywords.keyword_id as sk_keyword,
        keywords.account_id as account_id,
        keywords.campaign_id as campaign_id,
        keywords.campaign_name as campaign_name,
        keywords.adgroup_id as adgroup_id,
        keywords.adgroup_name as adgroup_name,
        keywords.criteria as keyword_name,
        keywords.keyword_match_type as match_type,
        sum((cast(keywords.cost as double) / 1000000)) as total_cost,
        keywords.date as sk_date,
        keywords.acc,
        keywords.dt
    FROM stitch.clean_keywords keywords
    GROUP BY 1,2,3,4,5,6,7,8,10,11,12
)
SELECT keywords.sk_keyword,
    keywords.account_id,
    keywords.campaign_id,
    keywords.adgroup_id,
    keywords.acc,
    keywords.campaign_name,
    keywords.adgroup_name,
    keywords.keyword_name,
    keywords.total_cost,
    COALESCE(mobile_devices.total_clicks, 0) as mobile_clicks,
    COALESCE(tablet_devices.total_clicks, 0) as tablet_clicks,
    COALESCE(computer_devices.total_clicks, 0) as computer_clicks,
    (COALESCE(mobile_devices.total_clicks, 0) + COALESCE(tablet_devices.total_clicks, 0) + COALESCE(computer_devices.total_clicks, 0)) as sum_clicks,
    keywords.sk_date
FROM keywords
LEFT JOIN computer_devices
    ON computer_devices.account_id = keywords.account_id
        AND computer_devices.campaign_id = keywords.campaign_id
        AND computer_devices.adgroup_id = keywords.adgroup_id
        AND computer_devices.keyword_id = keywords.sk_keyword
        AND computer_devices.date = keywords.sk_date
LEFT JOIN mobile_devices
    ON mobile_devices.account_id = keywords.account_id
        AND mobile_devices.campaign_id = keywords.campaign_id
        AND mobile_devices.adgroup_id = keywords.adgroup_id
        AND mobile_devices.keyword_id = keywords.sk_keyword
        AND mobile_devices.date = keywords.sk_date
LEFT JOIN tablet_devices
    ON tablet_devices.account_id = keywords.account_id
        AND tablet_devices.campaign_id = keywords.campaign_id
        AND tablet_devices.adgroup_id = keywords.adgroup_id
        AND tablet_devices.keyword_id = keywords.sk_keyword
        AND tablet_devices.date = keywords.sk_date
WHERE keywords.acc = '{account}' AND keywords.dt = '{date}'