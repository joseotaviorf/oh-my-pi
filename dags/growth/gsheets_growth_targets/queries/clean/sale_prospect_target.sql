SELECT
  NULLIF(funnel_side, '') AS funnel_side,
  NULLIF(city_group, '') AS city_group,
  NULLIF(operation_channel, '') AS operation_channel,
  NULLIF(referral_type, '') AS referral_type,
  NULLIF(campaign_strategy_intent, '') AS campaign_strategy_intent,
  NULLIF(behavior_type, '') AS behavior_type,
  NULLIF(medium, '') AS medium,
  CAST(REPLACE(NULLIF(nbp, ''), ',', '') AS FLOAT) AS nbp,
  CAST(REPLACE(NULLIF(rbp, ''), ',', '') AS FLOAT) AS rbp,
  CAST(NULLIF(date, '') AS DATE) AS date
FROM
  datalake_gsheets_raw.sale_prospect_target