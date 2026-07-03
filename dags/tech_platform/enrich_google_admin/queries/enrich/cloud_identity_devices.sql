WITH devices_scoped AS (
    SELECT
        *
    FROM
        datalake_google_admin_clean.cloud_identity_devices
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
users_scoped AS (
    SELECT
        *
    FROM
        datalake_google_admin_clean.cloud_identity_device_users
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
-- Single anchor date: the latest day present in BOTH tables within the batch window.
-- Prevents cross-snapshot joins when one source load fails or is partial.
-- COALESCE on the users side guards against an empty users_scoped (LEAST(x, NULL) = NULL
-- in Spark SQL, which would drop all devices with extraction_type: full).
anchor AS (
    SELECT
        LEAST(
            (SELECT MAX(MAKE_DATE(year, month, day)) FROM devices_scoped),
            COALESCE(
                (SELECT MAX(MAKE_DATE(year, month, day)) FROM users_scoped),
                (SELECT MAX(MAKE_DATE(year, month, day)) FROM devices_scoped)
            )
        ) AS d
),
latest_partition AS (
    SELECT
        s.*
    FROM
        devices_scoped AS s
        INNER JOIN anchor AS a ON MAKE_DATE(s.year, s.month, s.day) = a.d
),
ranked AS (
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
        day,
        ROW_NUMBER() OVER (
            PARTITION BY id_device
            ORDER BY
                ts_last_sync DESC NULLS LAST,
                nm_hostname ASC NULLS LAST
        ) AS rn
    FROM
        latest_partition
),
users_latest_partition AS (
    SELECT
        u.*
    FROM
        users_scoped AS u
        INNER JOIN anchor AS a ON MAKE_DATE(u.year, u.month, u.day) = a.d
),
primary_user AS (
    SELECT
        id_device,
        ds_user_email,
        ROW_NUMBER() OVER (
            PARTITION BY id_device
            ORDER BY
                ts_last_sync DESC NULLS LAST,
                ds_user_email ASC NULLS LAST
        ) AS urn
    FROM
        users_latest_partition
)
SELECT
    r.id_device,
    r.ds_serial_number,
    r.nm_hostname,
    r.nm_model,
    r.nm_manufacturer,
    r.ds_device_type,
    r.ds_os_version,
    r.ds_owner_type,
    r.ds_encryption_state,
    u.ds_user_email,
    r.ts_created,
    r.ts_last_sync,
    r.year,
    r.month,
    r.day
FROM
    ranked AS r
    LEFT JOIN primary_user AS u ON r.id_device = u.id_device
WHERE
    r.rn = 1
    AND (u.urn = 1 OR u.id_device IS NULL)
