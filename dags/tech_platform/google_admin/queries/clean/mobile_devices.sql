WITH ranked AS (
    SELECT
        resourceId AS id_resource,
        deviceId AS ds_device_id,
        serialNumber AS ds_serial_number,
        hardwareId AS ds_hardware_id,
        imei AS ds_imei,
        meid AS ds_meid,
        wifiMacAddress AS ds_wifi_mac_address,
        type AS ds_device_type,
        status AS ds_status,
        model AS nm_model,
        manufacturer AS nm_manufacturer,
        brand AS nm_brand,
        os AS ds_os,
        buildNumber AS ds_build_number,
        releaseVersion AS ds_release_version,
        kernelVersion AS ds_kernel_version,
        basebandVersion AS ds_baseband_version,
        bootloaderVersion AS ds_bootloader_version,
        securityPatchLevel AS ds_security_patch_level,
        ELEMENT_AT(email, 1) AS ds_user_email,
        ELEMENT_AT(name, 1) AS nm_user,
        networkOperator AS ds_network_operator,
        privilege AS ds_privilege,
        devicePasswordStatus AS ds_device_password_status,
        managedAccountIsOnOwnerProfile AS is_managed_account_on_owner_profile,
        supportsWorkProfile AS is_work_profile_supported,
        unknownSourcesStatus AS is_unknown_sources_enabled,
        adbStatus AS is_adb_enabled,
        developerOptionsStatus AS is_developer_options_enabled,
        TRY_CAST(firstSync AS TIMESTAMP) AS ts_first_sync,
        TRY_CAST(lastSync AS TIMESTAMP) AS ts_last_sync,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                year,
                month,
                day,
                resourceId
            ORDER BY
                TRY_CAST(lastSync AS TIMESTAMP) DESC NULLS LAST,
                deviceId ASC NULLS LAST
        ) AS rn
    FROM
        datalake_google_admin_raw.mobile_devices
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_resource,
    ds_device_id,
    ds_serial_number,
    ds_hardware_id,
    ds_imei,
    ds_meid,
    ds_wifi_mac_address,
    ds_device_type,
    ds_status,
    nm_model,
    nm_manufacturer,
    nm_brand,
    ds_os,
    ds_build_number,
    ds_release_version,
    ds_kernel_version,
    ds_baseband_version,
    ds_bootloader_version,
    ds_security_patch_level,
    ds_user_email,
    nm_user,
    ds_network_operator,
    ds_privilege,
    ds_device_password_status,
    is_managed_account_on_owner_profile,
    is_work_profile_supported,
    is_unknown_sources_enabled,
    is_adb_enabled,
    is_developer_options_enabled,
    ts_first_sync,
    ts_last_sync,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
