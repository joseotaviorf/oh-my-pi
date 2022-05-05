WITH manual_costs_by_platform AS (
    SELECT
        INT(REPLACE(dt_cost, '-', '')) AS id_date,
        'Not Mapped' AS origin,
        account_name,
        campaign_name,
        city_group,
        'Not Mapped' AS campaign_origin_acquisition,
        'Inbound' AS mkt_category,
        'Self-Service' AS mkt_flow,
        'Full Self-Service' AS mkt_completion,
        COALESCE(mkt_origin, 'Not Mapped') AS mkt_origin,
        COALESCE(mkt_channel, 'Not Mapped') AS mkt_channel,
        COALESCE(mkt_medium, 'Not Mapped') AS mkt_medium,
        COALESCE(mkt_source, 'Not Mapped') AS mkt_source,
        campaign_name AS utm_campaign,
        utm_term,
        utm_content,
        cost,
        COALESCE(side, 'Not Mapped') AS funnel_side,
        INLINE_OUTER(ARRAYS_ZIP(
            ARRAY(cost_share_desktop, cost_share_mobile, cost_share_other),
            ARRAY('Desktop', 'Mobile', 'Other')
        )) AS (platform_cost_factor, mkt_platform),
        COALESCE(cost_share_desktop, 0) AS cost_share_desktop,
        COALESCE(cost_share_mobile, 0) AS cost_share_mobile,
        COALESCE(cost_share_other, 0) AS cost_share_other
    FROM
        datalake_gsheets_clean.casa_mineira_marketing_manual_shared_costs
),

manual_costs_split AS (
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
        CASE
            WHEN cost_share_mobile + cost_share_desktop + cost_share_other = 0
                AND mkt_platform = 'Other'
            THEN 1
            WHEN cost_share_mobile + cost_share_desktop + cost_share_other = 1
            THEN COALESCE(platform_cost_factor, 0)
            WHEN cost_share_mobile + cost_share_desktop + cost_share_other > 0
                AND mkt_platform = 'Mobile'
            THEN 1
            ELSE 0
        END AS cost_factor,
        cost,
        id_date
    FROM
        manual_costs_by_platform
)

SELECT
    id_date,
    'manual' AS flow_type,
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
    cost * cost_factor AS cost
FROM
    manual_costs_split
WHERE
    (cost * cost_factor) > 0
