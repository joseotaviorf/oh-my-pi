WITH taxonomy_by_platform AS (
    SELECT
        campaign_origin_acquisition,
        mkt_category,
        mkt_flow,
        mkt_completion,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        side,
        account_name,
        report_type,
        ad_type,
        origin,
        INLINE_OUTER(ARRAYS_ZIP(
            COALESCE(SPLIT(cost_factor, ';'), ARRAY(NULL)),
            ARRAY('Desktop', 'Mobile', 'Other')
        )) AS (platform_cost_factor, mkt_platform)
    FROM
        datalake_gsheets_clean.casa_mineira_marketing_cost_taxonomy
),

filtered_media_costs AS (
    SELECT
        id_date,
        origin,
        account_name,
        campaign_name,
        utm_campaign,
        utm_term,
        utm_content,
        city_group,
        report_type,
        ad_type,
        mobile_cost,
        desktop_cost,
        other_cost,
        total_cost,
        CASE
            WHEN LOWER(campaign_name) LIKE '%branded%' THEN 'Branded'
            ELSE 'Other'
        END AS campaign_origin_acquisition
    FROM
        datalake_casa_mineira_consolidated_marketing_metrics.consolidated_media_metrics
    WHERE
        total_cost > 0
        AND LOWER(SPLIT(campaign_name, '[.]')[0]) <> 'zebra'
        AND id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
)

SELECT
    fmc.id_date,
    'automatic' AS flow_type,
    fmc.origin,
    fmc.account_name,
    fmc.campaign_name,
    fmc.utm_campaign,
    fmc.utm_term,
    fmc.utm_content,
    fmc.city_group,
    COALESCE(tp.campaign_origin_acquisition, 'Not Mapped') AS campaign_origin_acquisition,
    COALESCE(tp.mkt_category, 'Not Mapped') AS mkt_category,
    COALESCE(tp.mkt_flow, 'Not Mapped') AS mkt_flow,
    COALESCE(tp.mkt_completion, 'Not Mapped') AS mkt_completion,
    COALESCE(tp.mkt_origin, 'Not Mapped') AS mkt_origin,
    COALESCE(tp.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(tp.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(tp.mkt_source, 'Not Mapped') AS mkt_source,
    COALESCE(tp.mkt_platform, 'Not Mapped') AS mkt_platform,
    COALESCE(CASE
        WHEN tp.mkt_source='RTB House'
        THEN IF(fmc.utm_campaign RLIKE '^(1535|Campanha Casa Mineira Imóveis)', 'imobiliaria', 'portal')
        ELSE tp.side
        END, 'Not Mapped') AS funnel_side,
    COALESCE(
        fmc.total_cost * FLOAT(tp.platform_cost_factor),
        CASE
            WHEN tp.mkt_platform = 'Mobile' THEN fmc.mobile_cost
            WHEN tp.mkt_platform = 'Desktop' THEN fmc.desktop_cost
            WHEN tp.mkt_platform = 'Other' THEN fmc.other_cost
            ELSE fmc.total_cost
        END
    ) AS cost
FROM
    filtered_media_costs fmc
LEFT JOIN
    taxonomy_by_platform AS tp
        ON COALESCE(fmc.account_name, '') = COALESCE(tp.account_name, '')
        AND COALESCE(fmc.report_type, '') = COALESCE(tp.report_type, '')
        AND COALESCE(fmc.ad_type, 'other') = COALESCE(tp.ad_type, 'other')
        AND fmc.origin = tp.origin
        AND fmc.campaign_origin_acquisition = tp.campaign_origin_acquisition
