SELECT
  sk_media_setup,
  naming_convention_sufix,
  campaign_business_context,
  campaign_strategy_intent,
  behavior_type,
  campaign_landing_page,
  medium,
  source,
  prefix_campaign_business_context,
  prefix_campaign_strategy_intent,
  prefix_behavior_type,
  prefix_campaign_landing_page,
  prefix_funnel_side,
  prefix_medium,
  prefix_source,
  funnel_side,
  ts_combination_created,
  ts_load
FROM (
  SELECT
    ms.id_media_setup AS sk_media_setup,
    ms.naming_convention_sufix,
    ms.campaign_business_context,
    ms.campaign_strategy_intent,
    ms.behavior_type,
    ms.campaign_landing_page,
    ms.medium,
    ms.source,
    ms.prefix_campaign_business_context,
    ms.prefix_campaign_strategy_intent,
    ms.prefix_behavior_type,
    ms.prefix_campaign_landing_page,
    ms.prefix_funnel_side,
    ms.prefix_medium,
    ms.prefix_source,
    ms.funnel_side,
    ms.ts_combination_created,
    ms.ts_load,
    ROW_NUMBER() OVER (PARTITION BY ms.naming_convention_sufix ORDER BY ms.ts_load DESC) AS _w
  FROM datalake_growth_taxonomy.media_setup AS ms
) AS _t
WHERE
  _w = 1