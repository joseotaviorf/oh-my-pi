WITH scoped AS (
  SELECT
    *
  FROM datalake_iru_clean.managed_devices
  WHERE
    MAKE_DATE(year, month, day) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
), max_reading AS (
  SELECT
    MAX(MAKE_DATE(year, month, day)) AS d
  FROM scoped
), latest_partition AS (
  SELECT
    s.*
  FROM scoped AS s
  INNER JOIN max_reading AS m
    ON MAKE_DATE(s.year, s.month, s.day) = m.d
)
SELECT
  id_device,
  ds_serial_number,
  id_udid,
  nm_device,
  nm_model,
  ds_platform,
  ds_os_version,
  ds_supplemental_build_version,
  id_blueprint,
  nm_blueprint,
  ds_asset_tag,
  id_user,
  nm_user,
  ds_user_email,
  is_user_archived,
  is_user_active,
  ds_agent_version,
  ds_lost_mode_status,
  is_mdm_enabled,
  is_agent_installed,
  is_missing,
  is_removed,
  ts_first_enrollment,
  ts_last_enrollment,
  ts_last_check_in,
  year,
  month,
  day
FROM (
  SELECT
    id_device,
    ds_serial_number,
    id_udid,
    nm_device,
    nm_model,
    ds_platform,
    ds_os_version,
    ds_supplemental_build_version,
    id_blueprint,
    nm_blueprint,
    ds_asset_tag,
    id_user,
    nm_user,
    ds_user_email,
    is_user_archived,
    is_user_active,
    ds_agent_version,
    ds_lost_mode_status,
    is_mdm_enabled,
    is_agent_installed,
    is_missing,
    is_removed,
    ts_first_enrollment,
    ts_last_enrollment,
    ts_last_check_in,
    year,
    month,
    day,
    ROW_NUMBER() OVER (PARTITION BY id_device ORDER BY ts_last_check_in DESC, nm_device ASC NULLS LAST) AS _w
  FROM latest_partition
) AS _t
WHERE
  _w = 1
