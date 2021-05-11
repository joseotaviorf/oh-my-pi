WITH platforms AS (
    SELECT
        1 AS i,
        'Desktop' AS mkt_platform
    UNION ALL
    SELECT
        2,
        'Mobile'
    UNION ALL
    SELECT
        3,
        'Other'
),

taxonomy_by_platform AS (
    SELECT
        mcft.*,
        FLOAT(COALESCE(NULLIF(TRIM(SPLIT(cost_factor, ';')[p.i-1]), ''), '1.0')) AS fator_custo,
        p.mkt_platform
    FROM
        datalake_gsheets_clean.marketing_costs_full_taxonomy mcft
        CROSS JOIN
            platforms AS p
),

enriched_consolidated_media_costs AS (
    SELECT
        *,
        CASE WHEN campaign_name LIKE '%calc%' THEN
            'Calculator'
        ELSE
            'Other'
        END AS campaign_origin_acquisition
    FROM
        datalake_consolidated_marketing_costs.consolidated_media_costs
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
),

media_costs_with_taxonomy AS (
    SELECT
        ecmc.id_date,
        'automatic' AS flow_type,
        ecmc.origin,
        ecmc.account_name,
        ecmc.campaign_name,
        ecmc.utm_campaign,
        ecmc.utm_term,
        ecmc.utm_content,
        ecmc.city_group,
        COALESCE(tp.campaign_origin_acquisition, 'Not Mapped') AS campaign_origin_acquisition,
        COALESCE(tp.mkt_category, 'Not Mapped') AS mkt_category,
        COALESCE(tp.mkt_flow, 'Not Mapped') AS mkt_flow,
        COALESCE(tp.mkt_completion, 'Not Mapped') AS mkt_completion,
        COALESCE(tp.mkt_origin, 'Not Mapped') AS mkt_origin,
        COALESCE(tp.mkt_channel, 'Not Mapped') AS mkt_channel,
        COALESCE(tp.mkt_medium, 'Not Mapped') AS mkt_medium,
        COALESCE(tp.mkt_source, 'Not Mapped') AS mkt_source,
        COALESCE(tp.mkt_platform, 'Not Mapped') AS mkt_platform,
        COALESCE(tp.side, 'Not Mapped') AS funnel_side,
        tp.fator_custo,
        (CASE WHEN total_cost IS NULL THEN
            (CASE 
                WHEN tp.mkt_platform = 'Mobile' THEN mobile_cost
                WHEN tp.mkt_platform = 'Desktop' THEN desktop_cost
                WHEN tp.mkt_platform = 'Other' THEN other_cost
                WHEN tp.mkt_platform IS NULL AND total_cost IS NULL THEN
                    COALESCE(mobile_cost, 0) + COALESCE(desktop_cost, 0) + COALESCE(other_cost, 0)
            END)
            ELSE
                total_cost
        END) * FLOAT(COALESCE(tp.fator_custo, '1')) AS cost
    FROM
        enriched_consolidated_media_costs ecmc
        LEFT JOIN
            taxonomy_by_platform AS tp 
                ON COALESCE(ecmc.account_name, '') = COALESCE(tp.account_name, '')
                    AND COALESCE(ecmc.report_type, '') = COALESCE(tp.report_type, '')
                    AND ecmc.origin = tp.origin
                    AND ecmc.campaign_origin_acquisition = tp.campaign_origin_acquisition
)

SELECT 
    * 
FROM 
    media_costs_with_taxonomy 
WHERE
    cost > 0
