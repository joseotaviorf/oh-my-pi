SELECT
  NULLIF(business_context, '') AS business_context,
  NULLIF(city_group, '') AS city_group,
  NULLIF(funnel_side, '') AS funnel_side,
  NULLIF(campaign_strategy_intent, '') AS campaign_strategy_intent,
  NULLIF(behavior_type, '') AS behavior_type,
  NULLIF(medium, '') AS medium,
  CAST(REPLACE(NULLIF(cost, ''), ',', '') AS FLOAT) AS cost,
  CAST(NULLIF(date, '') AS DATE) AS date
FROM
  datalake_gsheets_raw.mkt_cost_target