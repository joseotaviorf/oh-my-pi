SELECT
  NULLIF(funnel_side, '') AS funnel_side,
  NULLIF(city_group, '') AS city_group,
  NULLIF(campaign_strategy_intent, '') AS campaign_strategy_intent,
  NULLIF(behavior_type, '') AS behavior_type,
  NULLIF(medium, '') AS medium,
  CAST(REPLACE(NULLIF(tof_users, ''), ',', '') AS FLOAT) AS tof_users,
  CAST(REPLACE(NULLIF(tof_events, ''), ',', '') AS FLOAT) AS tof_events,
  CAST(NULLIF(week_start, '') AS DATE) AS week_start
FROM
  datalake_gsheets_raw.rental_tof_weekly_target