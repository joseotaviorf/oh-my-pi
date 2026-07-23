SELECT
  id_user,
  full_name,
  phone_number,
  is_deleted,
  ts_created,
  ts_updated
FROM (
  SELECT
    id_user,
    full_name,
    phone_number,
    is_deleted,
    ts_created,
    ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_updated DESC) AS _w
  FROM datalake_mission_control_clean.user
) AS _t
WHERE
  _w = 1