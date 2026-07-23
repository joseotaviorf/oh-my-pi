WITH scoped AS (
  SELECT
    *
  FROM
    datalake_intune_clean.managed_devices
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
max_reading AS (
  SELECT
    MAX(MAKE_DATE(year, month, day)) AS d
  FROM
    scoped
),
latest_partition AS (
  SELECT
    s.*
  FROM
    scoped AS s
    INNER JOIN max_reading AS m ON MAKE_DATE(s.year, s.month, s.day) = m.d
)
SELECT
  id_device,
  id_azure_ad_device,
  nm_device,
  nm_managed_device,
  id_user,
  nm_user,
  ds_email_address,
  ds_user_principal_name,
  ds_owner_type,
  nm_manufacturer,
  nm_model,
  ds_serial_number,
  ds_device_enrollment_type,
  ds_device_registration_state,
  ds_management_agent,
  ds_operating_system,
  ds_os_version,
  ds_compliance_state,
  ds_management_state,
  is_encrypted,
  is_supervised,
  is_azure_ad_registered,
  is_eas_activated,
  id_eas_device,
  ds_jail_broken,
  ds_wifi_mac_address,
  qt_total_storage_bytes,
  qt_free_storage_bytes,
  ts_enrolled_utc,
  ts_last_sync_utc,
  ts_compliance_grace_expiration_utc,
  ts_management_certificate_expiration_utc,
  year,
  month,
  day
FROM
  latest_partition
QUALIFY
  ROW_NUMBER() OVER (
    PARTITION BY id_device
    ORDER BY
      ts_last_sync_utc DESC NULLS LAST,
      nm_device ASC NULLS LAST
  ) = 1
