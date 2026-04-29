SELECT
  id AS id_device,
  azureADDeviceId AS id_azure_ad_device,
  deviceName AS nm_device,
  managedDeviceName AS nm_managed_device,
  userId AS id_user,
  userDisplayName AS nm_user,
  emailAddress AS ds_email_address,
  userPrincipalName AS ds_user_principal_name,
  managedDeviceOwnerType AS ds_owner_type,
  manufacturer AS nm_manufacturer,
  model AS nm_model,
  serialNumber AS ds_serial_number,
  deviceEnrollmentType AS ds_device_enrollment_type,
  deviceRegistrationState AS ds_device_registration_state,
  managementAgent AS ds_management_agent,
  operatingSystem AS ds_operating_system,
  osVersion AS ds_os_version,
  complianceState AS ds_compliance_state,
  managementState AS ds_management_state,
  isEncrypted AS is_encrypted,
  isSupervised AS is_supervised,
  azureADRegistered AS is_azure_ad_registered,
  easActivated AS is_eas_activated,
  easDeviceId AS id_eas_device,
  jailBroken AS ds_jail_broken,
  wiFiMacAddress AS ds_wifi_mac_address,
  totalStorageSpaceInBytes AS qt_total_storage_bytes,
  freeStorageSpaceInBytes AS qt_free_storage_bytes,
  CASE
    WHEN enrolledDateTime IN ('0001-01-01T00:00:00Z', '9999-12-31T23:59:59Z') THEN NULL
    ELSE CAST(enrolledDateTime AS TIMESTAMP)
  END AS ts_enrolled_utc,
  CASE
    WHEN lastSyncDateTime IN ('0001-01-01T00:00:00Z', '9999-12-31T23:59:59Z') THEN NULL
    ELSE CAST(lastSyncDateTime AS TIMESTAMP)
  END AS ts_last_sync_utc,
  CASE
    WHEN complianceGracePeriodExpirationDateTime IN ('0001-01-01T00:00:00Z', '9999-12-31T23:59:59Z') THEN NULL
    ELSE CAST(complianceGracePeriodExpirationDateTime AS TIMESTAMP)
  END AS ts_compliance_grace_expiration_utc,
  CASE
    WHEN managementCertificateExpirationDate IN ('0001-01-01T00:00:00Z', '9999-12-31T23:59:59Z') THEN NULL
    ELSE CAST(managementCertificateExpirationDate AS TIMESTAMP)
  END AS ts_management_certificate_expiration_utc,
  year,
  month,
  day
FROM datalake_intune_raw.managed_devices
WHERE MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
