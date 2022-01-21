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

taxonomy_by_platform AS (
    SELECT
        mcft.*,
        FLOAT(NULLIF(TRIM(SPLIT(cost_factor, ';')[p.i]), '')) AS cost_factor_enriched,
        p.mkt_platform
    FROM
        datalake_gsheets_clean.marketing_costs_full_taxonomy mcft
        CROSS JOIN
            platforms AS p
),

enriched_consolidated_media_metrics AS (
    SELECT
        *,
        CASE
            WHEN LOWER(campaign_name) LIKE '%calc%'
                THEN 'Calculator'
            WHEN LOWER(campaign_name) LIKE '%newchannel%'
                THEN 'New Channels'
            ELSE 'Other'
        END AS campaign_origin_acquisition
    FROM
        datalake_consolidated_marketing_metrics.consolidated_media_metrics
    WHERE
        id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
),

media_costs_with_taxonomy AS (
    SELECT
        ecmm.id_date,
        'automatic' AS flow_type,
        ecmm.origin,
        ecmm.account_name,
        ecmm.campaign_name,
        ecmm.utm_campaign,
        ecmm.utm_term,
        ecmm.utm_content,
        ecmm.city_group,
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
        CASE 
            WHEN tp.cost_factor_enriched IS NULL THEN
                -- Cost/Platform defined in API/Source
                CASE 
                    WHEN tp.mkt_platform = 'Mobile' THEN mobile_cost
                    WHEN tp.mkt_platform = 'Desktop' THEN desktop_cost
                    WHEN tp.mkt_platform = 'Other' THEN other_cost
                    ELSE total_cost
                END
            ELSE 
                -- Cost/Platform defined in taxonomy
                total_cost * tp.cost_factor_enriched
        END AS cost
    FROM
        enriched_consolidated_media_metrics ecmm
        LEFT JOIN
            taxonomy_by_platform AS tp 
                ON COALESCE(ecmm.account_name, '') = COALESCE(TRIM(tp.account_name), '')
                    AND COALESCE(ecmm.report_type, '') = COALESCE(TRIM(tp.report_type), '')
                    AND COALESCE(ecmm.ad_type, 'other') = COALESCE(TRIM(tp.ad_type), 'other')
                    AND ecmm.origin = TRIM(tp.origin)
                    AND ecmm.campaign_origin_acquisition = TRIM(tp.campaign_origin_acquisition)
)

SELECT 
    * 
FROM 
    media_costs_with_taxonomy 
WHERE
    cost > 0
    AND LOWER(SPLIT(campaign_name, '[.]')[0]) <> 'zebra'
