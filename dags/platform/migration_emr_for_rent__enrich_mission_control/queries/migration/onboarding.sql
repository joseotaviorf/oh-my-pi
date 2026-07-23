SELECT
  id,
  id_contract,
  id_google_drive,
  status,
  property_type,
  key_location,
  key_location_details,
  version,
  is_deleted,
  ts_created,
  ts_updated,
  ts_last_synced
FROM (
  SELECT
    id,
    id_contract,
    id_google_drive,
    status,
    property_type,
    key_location,
    key_location_details,
    version,
    is_deleted,
    ts_created,
    ts_updated,
    ts_last_synced,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS _w
  FROM datalake_mission_control_clean.onboarding
) AS _t
WHERE
  _w = 1