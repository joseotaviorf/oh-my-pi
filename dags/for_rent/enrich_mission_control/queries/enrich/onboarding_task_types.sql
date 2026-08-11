SELECT
  id,
  user_type,
  type,
  is_active,
  ts_created,
  ts_updated
FROM (
  SELECT
    id,
    user_type,
    type,
    is_active,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_mission_control_clean.onboarding_task_types
) AS _t
WHERE
  _w = 1