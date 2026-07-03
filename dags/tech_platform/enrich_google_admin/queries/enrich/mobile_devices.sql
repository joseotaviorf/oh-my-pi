WITH scoped AS (
    SELECT
        *
    FROM
        datalake_google_admin_clean.mobile_devices
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
),
ranked AS (
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
        day,
        ROW_NUMBER() OVER (
            PARTITION BY id_resource
            ORDER BY
                ts_last_sync DESC NULLS LAST,
                ds_device_id ASC NULLS LAST
        ) AS rn
    FROM
        latest_partition
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
