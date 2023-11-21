SELECT
  id_user,
  full_name,
  phone_number,
  is_deleted,
  ts_created,
  ts_updated
FROM
  datalake_mission_control_clean.user
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_updated DESC) = 1