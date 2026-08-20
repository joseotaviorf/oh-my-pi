WITH standard_names AS (
    SELECT 
    id AS id_sheet,
    medium AS utm_medium,
    source AS utm_source,
    campaign AS utm_campaign,
    mkt_medium AS medium,
    mkt_source AS source,
    audience AS campaign_strategy_intent,
    REPLACE(payment_type, '-', ' ') AS behavior_type,
    campaign_context AS campaign_business_context,
    funnel_side,
    landing_page AS campaign_landing_page,
    owner
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY campaign, medium, source ORDER BY id) AS rn
        FROM datalake_gsheets_clean.dict_taxonomy_supply
    ) ranked
    WHERE rn = 1
),

base AS (
    SELECT 
        med.id_media_setup, 
        dic.*
    FROM standard_names AS dic
    LEFT JOIN datalake_growth_taxonomy.media_setup AS med
    ON (LOWER(dic.funnel_side) = LOWER(med.funnel_side))
        AND (LOWER(dic.campaign_landing_page) = LOWER(med.campaign_landing_page))
        AND (LOWER(dic.campaign_strategy_intent) = LOWER(med.campaign_strategy_intent))
        AND (LOWER(dic.behavior_type) = LOWER(med.behavior_type))
        AND (LOWER(dic.medium) = LOWER(med.medium))
        AND (LOWER(dic.source) = LOWER(med.source))
        AND (LOWER(dic.campaign_business_context) = LOWER(med.campaign_business_context))
)

SELECT 
    id_sheet,
    id_media_setup,
    utm_campaign,
    utm_medium,
    utm_source,
    campaign_strategy_intent,
    behavior_type,
    medium,
    source,
    campaign_business_context,
    campaign_landing_page,
    owner,
    funnel_side
FROM base