WITH platforms AS (
    SELECT
        0 AS i,
        'Desktop' AS mkt_platform
    UNION ALL
    SELECT
        1,
        'Mobile'
    UNION ALL
    SELECT
        2,
        'Other'
),
manual_costs AS (
    SELECT
        INT(REPLACE(dt_cost, '-', '')) AS id_date,
        'manual' AS flow_type,
        STRING(NULL) AS origin,
        account_name,
        campaign_name,
        CASE
            WHEN LOWER(campaign_name) LIKE '%calc%' THEN 'Calculator'
            WHEN LOWER(campaign_name) LIKE '%newchannel%' THEN 'New Channels'
            ELSE 'Other'
        END AS campaign_origin_acquisition,
        city_group,
        'Inbound' AS mkt_category,
        'Self-Service' AS mkt_flow,
        'Full Self-Service' AS mkt_completion,
        p.mkt_platform,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        campaign_name AS utm_campaign,
        utm_term,
        utm_content,
        FLOAT(COST) AS raw_cost,
        CASE 
            WHEN (
                COALESCE(cost_share_mobile, 0) + 
                COALESCE(cost_share_desktop, 0) + 
                COALESCE(cost_share_other, 0)
            ) = 1 
            THEN
                CASE
                    WHEN p.mkt_platform = 'Mobile' THEN COALESCE(cost_share_mobile, 0)
                    WHEN p.mkt_platform = 'Desktop' THEN COALESCE(cost_share_desktop, 0)
                    WHEN p.mkt_platform = 'Other' THEN COALESCE(cost_share_other, 0)
                END
            ELSE
                CASE
                    WHEN p.mkt_platform = 'Mobile' THEN 1
                ELSE 0
                END
        END AS cost_factor,
        side AS funnel_side,
        cost_share_desktop,
        cost_share_mobile,
        cost_share_other
    FROM
        datalake_gsheets_clean.mexico_marketing_manual_shared_costs
    CROSS JOIN
        platforms AS p
)
SELECT
    origin,
    account_name,
    campaign_name,
    utm_campaign,
    utm_term,
    utm_content,
    city_group,
    campaign_origin_acquisition,
    mkt_category,
    mkt_flow,
    mkt_completion,
    mkt_origin,
    mkt_channel,
    mkt_medium,
    mkt_source,
    mkt_platform,
    funnel_side,
    CAST(raw_cost * cost_factor AS FLOAT) AS cost,
    id_date,
    flow_type
FROM
    manual_costs
WHERE
    (raw_cost * cost_factor) != 0
    AND LOWER(SUBSTRING(NVL(campaign_name, ''), 1, 3)) <> 'dsa'
