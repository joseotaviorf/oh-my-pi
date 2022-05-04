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
        account_name AS account_name,
        campaign_name AS campaign_name,
        city_group AS city_group,
        mkt_origin AS mkt_origin,
        mkt_channel AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        campaign_name AS utm_campaign,
        utm_term AS utm_term,
        utm_content AS utm_content,
        FLOAT(COST) AS raw_cost,
        side AS side,
        cost_share_desktop,
        cost_share_mobile,
        cost_share_other
    FROM
        datalake_gsheets_clean.marketing_costs_manual_shared_costs
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
),

city_group_share_rules AS (
    SELECT
        INT(REPLACE(dt_cost, '-', '')) AS id_date,
        account_name AS account_name,
        campaign_name AS campaign_name,
        r.city_group AS city_group,
        mkt_origin AS mkt_origin,
        mkt_channel AS mkt_channel,
        mkt_medium AS mkt_medium,
        mkt_source AS mkt_source,
        campaign_name AS utm_campaign,
        utm_term AS utm_term,
        utm_content AS utm_content,
        FLOAT(COST) * r.share AS raw_cost,
        side AS side,
        cost_share_desktop,
        cost_share_mobile,
        cost_share_other
    FROM
        datalake_gsheets_clean.marketing_costs_name_convention_shared_costs s
    JOIN
        datalake_marketing_costs_sharing_rules.old_sharing_rules AS r 
            ON INT(REPLACE(dt_cost, '-', '')) = r.id_date
            AND s.id_rule = r.id_rule
            AND s.side = r.funnel_side
    WHERE
        DATE(dt_cost) >= DATE('2021-01-01') -- manual costs from before this date are included in historical partition
),

enriched_manual_costs AS (
    SELECT
        STRING(NULL) AS origin,
        account_name,
        campaign_name,
        utm_campaign,
        utm_term,
        utm_content,
        city_group,
        CASE
            WHEN LOWER(campaign_name) LIKE '%calc%' THEN 'Calculator'
            WHEN LOWER(campaign_name) LIKE '%newchannel%' THEN 'New Channels'
            ELSE 'Other'
        END AS campaign_origin_acquisition,
        'Inbound' AS mkt_category,
        'Self-Service' AS mkt_flow,
        'Full Self-Service' AS mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        p.mkt_platform,
        side AS funnel_side,
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
        raw_cost,
        id_date,
        'manual' AS flow_type
    FROM
        (
            SELECT
                *
            FROM
                manual_costs
            UNION ALL
            SELECT
                *
            FROM
              city_group_share_rules
        )
    CROSS JOIN
        platforms p
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
    raw_cost * cost_factor AS cost,
    id_date,
    flow_type
FROM
    enriched_manual_costs
WHERE
    (raw_cost * cost_factor) > 0
    AND LOWER(SUBSTRING(NVL(campaign_name, ''), 1, 3)) <> 'dsa'
