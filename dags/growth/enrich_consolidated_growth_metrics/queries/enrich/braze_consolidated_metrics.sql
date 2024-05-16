WITH
notification_indica_ai AS (
    SELECT
        notification_count,
        CASE
            WHEN canvas_name ilike 'acq%' THEN 'ia_notification_acq'
            ELSE 'ia_notification_eng'
        END AS mkt_vertical,
        CASE
            WHEN rule_status = 'SupplyAffiliateSms' THEN 'SMS'
            WHEN rule_status = 'SupplyDoormanNews'
            OR rule_status = 'SupplyAffiliateGenericMessage' THEN 'Whatsapp'
            ELSE 'não'
        END AS ia_general,
        CASE
            WHEN canvas_name ilike '%doorman%' THEN 'Doorman'
            WHEN canvas_name ilike '%agent%' THEN 'Indica Aí - Agents'
            ELSE 'Indica Aí - General'
        END AS context,
        'indica_ai_notification' AS account_name,
        dt_webhook_sent
    FROM
        datalake_braze_webhook_notification.webhook_notification_volumes
    WHERE
        dt_webhook_sent BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND rule_status IN ('SupplyAffiliateGenericMessage', 'SupplyDoormanNews', 'SupplyAffiliateSms')
),
total_cost_per_notification_type AS (
    SELECT
        CONCAT(mkt_vertical, '_', ia_general) AS campaign_name,
        account_name,
        context,
        ia_general,
        dt_webhook_sent,
        CASE
            WHEN ia_general = 'SMS' THEN SUM(notification_count) * 0.046
            WHEN ia_general = 'Whatsapp' THEN SUM(notification_count) * 0.007 * 5.4
            ELSE 0.00
        END AS cost
    FROM
        notification_indica_ai
    GROUP BY 1,2,3,4,5
),
consolidate_braze_notification_costs AS (
    SELECT
        INT(YEAR(dt_webhook_sent)*10000 + MONTH(dt_webhook_sent)*100 + DAY(dt_webhook_sent)) AS id_date,
        'braze' AS origin,
        account_name,
        campaign_name,
        ia_general,
        context,
        'affiliates' AS funnel_side,
        CAST(NULL AS STRING) AS utm_campaign,
        CAST(NULL AS STRING) AS utm_term,
        CAST(NULL AS STRING) AS utm_content,
        cost
    FROM
        total_cost_per_notification_type
),
apply_sharing_rules AS (
SELECT
    cbnc.id_date,
    cbnc.origin,
    cbnc.account_name,
    cbnc.campaign_name,
    cbnc.ia_general,
    cbnc.context,
    sr.business_context AS business_context,
    COALESCE(sr.city_group,'Not Mapped') AS city_group,
    cbnc.funnel_side,
    cbnc.utm_campaign,
    cbnc.utm_term,
    cbnc.utm_content,
    cbnc.cost * COALESCE(sr.share, 1) AS cost
FROM
    consolidate_braze_notification_costs cbnc
    LEFT JOIN datalake_marketing_costs_sharing_rules.a028a sr
        ON cbnc.id_date = sr.id_date
WHERE
    cost <> 0
    AND context = 'Indica Aí - General'
UNION ALL
SELECT
    cbnc.id_date,
    cbnc.origin,
    cbnc.account_name,
    cbnc.campaign_name,
    cbnc.ia_general,
    cbnc.context,
    sr.business_context AS business_context,
    COALESCE(sr.city_group,'Not Mapped') AS city_group,
    cbnc.funnel_side,
    cbnc.utm_campaign,
    cbnc.utm_term,
    cbnc.utm_content,
    cbnc.cost * COALESCE(sr.share, 1) AS cost
FROM
    consolidate_braze_notification_costs cbnc
    LEFT JOIN datalake_marketing_costs_sharing_rules.a034a sr
        ON cbnc.id_date = sr.id_date
WHERE
    cost <> 0
    AND context = 'Indica Aí - Agents'
UNION ALL
SELECT
    cbnc.id_date,
    cbnc.origin,
    cbnc.account_name,
    cbnc.campaign_name,
    cbnc.ia_general,
    cbnc.context,
    sr.business_context AS business_context,
    COALESCE(sr.city_group,'Not Mapped') AS city_group,
    cbnc.funnel_side,
    cbnc.utm_campaign,
    cbnc.utm_term,
    cbnc.utm_content,
    cbnc.cost * COALESCE(sr.share, 1) AS cost
FROM
    consolidate_braze_notification_costs cbnc
    LEFT JOIN datalake_marketing_costs_sharing_rules.a033a sr
        ON cbnc.id_date = sr.id_date
WHERE
    cost <> 0
    AND context = 'Doorman'
),
aux_business_context AS (
    SELECT
        'sale' AS business_context
    UNION ALL
    SELECT
        'rent' AS business_context
),
aux_business_context_share_rule AS (
    SELECT
        city_group,
        business_context
    FROM
        datalake_region.region
        CROSS JOIN aux_business_context
    WHERE
        city_group IN ('RMSP','Rio de Janeiro','Belo Horizonte','Campinas','Porto Alegre')
    GROUP BY 1,2
)
SELECT
    asr.id_date,
    asr.origin,
    asr.account_name,
    CASE
        WHEN abc.city_group IS NOT NULL THEN CONCAT(asr.campaign_name, '_', abc.business_context)
        ELSE CONCAT(asr.campaign_name, '_', 'rent')
    END AS campaign_name,
    asr.business_context,
    asr.ia_general,
    asr.context,
    asr.city_group,
    asr.funnel_side,
    asr.utm_campaign,
    asr.utm_term,
    asr.utm_content,
    CASE
        WHEN abc.city_group IS NOT NULL THEN 0.5 * asr.cost
        ELSE asr.cost
    END AS cost
FROM
    apply_sharing_rules asr
    LEFT JOIN aux_business_context_share_rule abc
        ON asr.city_group = abc.city_group
