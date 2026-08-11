SELECT
  id,
  id_onboarding,
  type_identifier,
  user_role_target_type,
  is_deleted,
  ts_created,
  ts_updated
FROM (
  SELECT
    id,
    id_onboarding,
    type_identifier,
    user_role_target_type,
    is_deleted,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_mission_control_clean.onboarding_action
) AS _t
WHERE
  _w = 1