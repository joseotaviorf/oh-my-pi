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
),
naming_convention_prefixes AS (
  SELECT
    sk_media_setup,
    LEFT(campaign_strategy_intent,3) AS prefix_campaign_strategy_intent,
    COALESCE(LEFT(SPLIT(behavior_type, " ")[0],3) ||LEFT(SPLIT(behavior_type, " ")[1],3), LEFT(behavior_type, 3)) AS prefix_behavior_type,
    COALESCE(LEFT(SPLIT(campaign_landing_page, " ")[0],3) ||LEFT(SPLIT(campaign_landing_page, " ")[1],3), LEFT(campaign_landing_page, 3)) AS prefix_campaign_landing_page,
    LEFT(campaign_business_context,4) AS prefix_campaign_business_context,
    LEFT(REPLACE(medium, ' ', ''), 20) AS prefix_medium,
    LEFT(REPLACE(source, ' ', ''), 20) AS prefix_source,
    LEFT(funnel_side,1) AS prefix_funnel_side,
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
    funnel_side,
    dict_source
  FROM
    unified_dict
)    

SELECT
  sk_media_setup,
  CONCAT_WS(".",
      prefix_campaign_business_context,
      prefix_campaign_strategy_intent,
      prefix_behavior_type,
      prefix_campaign_landing_page,
      prefix_funnel_side,
      prefix_medium,
      prefix_source
  ) AS naming_convention_sufix,
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
  funnel_side,
  dict_source
  FROM
    naming_convention_prefixes 
  QUALIFY ROW_NUMBER() OVER (
      PARTITION BY 
        utm_campaign,
        utm_medium,
        utm_source
      ORDER BY
        dict_source = 'demand' DESC
    ) = 1