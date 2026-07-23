WITH scoped AS (
  SELECT
    *
  FROM datalake_zscaler_clean.managed_devices
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
  ds_mac_address,
  nm_hostname,
  ds_user_email,
  nm_owner,
  nm_device_model,
  nm_manufacturer,
  ds_os_version,
  ds_agent_version,
  nm_policy,
  nm_company,
  ds_registration_state,
  cd_device_type,
  cd_device_state,
  cd_vpn_state,
  ds_tunnel_version,
  ds_architecture,
  ds_hardware_fingerprint,
  qt_download_count,
  ts_registration,
  ts_last_seen,
  ts_config_download,
  ts_keep_alive,
  year,
  month,
  day
FROM (
  SELECT
    id_device,
    ds_mac_address,
    nm_hostname,
    ds_user_email,
    nm_owner,
    nm_device_model,
    nm_manufacturer,
    ds_os_version,
    ds_agent_version,
    nm_policy,
    nm_company,
    ds_registration_state,
    cd_device_type,
    cd_device_state,
    cd_vpn_state,
    ds_tunnel_version,
    ds_architecture,
    ds_hardware_fingerprint,
    qt_download_count,
    ts_registration,
    ts_last_seen,
    ts_config_download,
    ts_keep_alive,
    year,
    month,
    day,
    ROW_NUMBER() OVER (PARTITION BY id_device ORDER BY ts_last_seen DESC, nm_hostname ASC NULLS LAST) AS _w
  FROM latest_partition
) AS _t
WHERE
  _w = 1
