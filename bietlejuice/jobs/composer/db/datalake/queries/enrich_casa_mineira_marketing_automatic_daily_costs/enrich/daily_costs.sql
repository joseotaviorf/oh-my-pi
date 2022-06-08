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
)

SELECT
    cmm.id_date,
    'automatic' AS flow_type,
    cmm.origin,
    cmm.account_name,
    cmm.campaign_name,
    cmm.utm_campaign,
    cmm.utm_term,
    cmm.utm_content,
    cmm.city_group,
    COALESCE(tbp.campaign_origin_acquisition, 'Not Mapped') AS campaign_origin_acquisition,
    COALESCE(tbp.mkt_category, 'Not Mapped') AS mkt_category,
    COALESCE(tbp.mkt_flow, 'Not Mapped') AS mkt_flow,
    COALESCE(tbp.mkt_completion, 'Not Mapped') AS mkt_completion,
    COALESCE(tbp.mkt_origin, 'Not Mapped') AS mkt_origin,
    COALESCE(tbp.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(tbp.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(tbp.mkt_source, 'Not Mapped') AS mkt_source,
    COALESCE(tbp.mkt_platform, 'Not Mapped') AS mkt_platform,
    COALESCE(
        CASE
            WHEN tbp.mkt_source='RTB House'
            THEN IF(cmm.utm_campaign RLIKE '^(1535|Campanha Casa Mineira Imóveis)', 'imobiliaria', 'portal')
            ELSE tbp.side
        END, 'Not Mapped'
    ) AS funnel_side,
    COALESCE(
        cmm.total_cost * FLOAT(tbp.platform_cost_factor),
        CASE
            WHEN tbp.mkt_platform = 'Mobile' THEN cmm.mobile_cost
            WHEN tbp.mkt_platform = 'Desktop' THEN cmm.desktop_cost
            WHEN tbp.mkt_platform = 'Other' THEN cmm.other_cost
            ELSE cmm.total_cost
        END
    ) AS cost
FROM
    datalake_casa_mineira_consolidated_marketing_metrics.consolidated_media_metrics cmm
LEFT JOIN
    taxonomy_by_platform AS tbp
        ON COALESCE(cmm.account_name, '') = COALESCE(tbp.account_name, '')
        AND COALESCE(cmm.report_type, '') = COALESCE(tbp.report_type, '')
        AND COALESCE(cmm.ad_type, 'other') = COALESCE(tbp.ad_type, 'other')
        AND cmm.origin = tbp.origin
        AND cmm.campaign_origin_acquisition = tbp.campaign_origin_acquisition
WHERE
    cmm.id_date = INT(REPLACE(DATE('{year}-{month}-{day}'), '-', ''))
    AND cmm.total_cost > 0
    AND LOWER(SPLIT(cmm.campaign_name, '[.]')[0]) <> 'zebra'
