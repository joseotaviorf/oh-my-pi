WITH scoped AS (
  SELECT
    *
  FROM datalake_crowdstrike_clean.managed_devices
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
  id_cid,
  nm_hostname,
  ds_platform,
  id_platform,
  ds_os_version,
  ds_os_build,
  ds_major_version,
  ds_minor_version,
  ds_agent_version,
  ds_external_ip,
  ds_local_ip,
  ds_mac_address,
  ds_machine_domain,
  nm_last_login_user,
  id_last_login_uid,
  id_last_login_user_sid,
  id_config_base,
  id_config_build,
  id_config_platform,
  ds_criticality,
  ds_containment_status,
  ds_reduced_functionality_mode,
  ds_rtr_state,
  ds_safe_mode,
  ts_first_seen,
  ts_last_seen,
  ts_last_login,
  ts_agent_local_time,
  year,
  month,
  day
FROM (
  SELECT
    id_device,
    id_cid,
    nm_hostname,
    ds_platform,
    id_platform,
    ds_os_version,
    ds_os_build,
    ds_major_version,
    ds_minor_version,
    ds_agent_version,
    ds_external_ip,
    ds_local_ip,
    ds_mac_address,
    ds_machine_domain,
    nm_last_login_user,
    id_last_login_uid,
    id_last_login_user_sid,
    id_config_base,
    id_config_build,
    id_config_platform,
    ds_criticality,
    ds_containment_status,
    ds_reduced_functionality_mode,
    ds_rtr_state,
    ds_safe_mode,
    ts_first_seen,
    ts_last_seen,
    ts_last_login,
    ts_agent_local_time,
    year,
    month,
    day,
    ROW_NUMBER() OVER (PARTITION BY id_device ORDER BY ts_last_seen DESC, nm_hostname ASC NULLS LAST) AS _w
  FROM latest_partition
) AS _t
WHERE
  _w = 1
