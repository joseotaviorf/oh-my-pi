WITH ranked AS (
    SELECT
        deviceId AS id_device,
        serialNumber AS ds_serial_number,
        hostname AS nm_hostname,
        model AS nm_model,
        manufacturer AS nm_manufacturer,
        deviceType AS ds_device_type,
        osVersion AS ds_os_version,
        ownerType AS ds_owner_type,
        encryptionState AS ds_encryption_state,
        TRY_CAST(createTime AS TIMESTAMP) AS ts_created,
        TRY_CAST(lastSyncTime AS TIMESTAMP) AS ts_last_sync,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                year,
                month,
                day,
                deviceId
            ORDER BY
                TRY_CAST(lastSyncTime AS TIMESTAMP) DESC NULLS LAST,
                hostname ASC NULLS LAST
        ) AS rn
    FROM
        datalake_google_admin_raw.cloud_identity_devices
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_device,
    ds_serial_number,
    nm_hostname,
    nm_model,
    nm_manufacturer,
    ds_device_type,
    ds_os_version,
    ds_owner_type,
    ds_encryption_state,
    ts_created,
    ts_last_sync,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
