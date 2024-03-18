WITH union_tb AS (
  SELECT 
    utm_campaign,
    utm_medium,
    utm_source,
    sk_media_setup,
    campaign_strategy_intent,
    behavior_type,
    medium,
    source,
    campaign_business_context,
    'NA' AS campaign_landing_page,
    owner,
    funnel_side,
    'demand' AS dict_source
  FROM datalake_growth_taxonomy.demand_taxonomy_dictionary
  UNION ALL
  SELECT 
    utm_campaign,
    utm_medium,
    utm_source,
    id_media_setup AS sk_media_setup,
    campaign_strategy_intent,
    behavior_type,
    medium,
    source,
    campaign_business_context,
    campaign_landing_page,
    owner,
    funnel_side,
    'supply' AS dict_source
  FROM datalake_growth_taxonomy.supply_taxonomy_dictionary
),
unified_dict AS (
    SELECT 
    SF_NORMALIZE_STRING(utm_campaign) AS utm_campaign,
    SF_NORMALIZE_STRING(utm_medium) AS utm_medium,
    SF_NORMALIZE_STRING(utm_source) AS utm_source,
    sk_media_setup,
    SF_NORMALIZE_STRING(campaign_strategy_intent) AS campaign_strategy_intent,
    SF_NORMALIZE_STRING(behavior_type) AS behavior_type,
    SF_NORMALIZE_STRING(medium) AS medium,
    SF_NORMALIZE_STRING(source) AS source,
    SF_NORMALIZE_STRING(campaign_business_context) AS campaign_business_context,
    SF_NORMALIZE_STRING(campaign_landing_page) AS campaign_landing_page,
    SF_NORMALIZE_STRING(owner) AS owner,
    SF_NORMALIZE_STRING(funnel_side) AS funnel_side,
    SF_NORMALIZE_STRING(dict_source) AS dict_source
    FROM union_tb
)

SELECT
    *
  FROM
    unified_dict 
  QUALIFY ROW_NUMBER() OVER (
      PARTITION BY 
        utm_campaign,
        utm_medium,
        utm_source
      ORDER BY
        dict_source = 'demand' DESC
    ) = 1