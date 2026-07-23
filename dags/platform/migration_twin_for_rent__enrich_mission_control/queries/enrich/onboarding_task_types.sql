SELECT
  id,
  user_type,
  type,
  is_active,
  ts_created,
  ts_updated
FROM
  datalake_mission_control_clean.onboarding_task_types
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1