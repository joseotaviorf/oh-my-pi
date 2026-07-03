WITH ranked AS (
    SELECT
        SPLIT(name, '/')[3] AS id_device,
        userEmail AS ds_user_email,
        managementState AS ds_management_state,
        passwordState AS ds_password_state,
        userAgent AS ds_user_agent,
        TRY_CAST(firstSyncTime AS TIMESTAMP) AS ts_first_sync,
        TRY_CAST(lastSyncTime AS TIMESTAMP) AS ts_last_sync,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                year,
                month,
                day,
                SPLIT(name, '/')[3],
                userEmail
            ORDER BY
                TRY_CAST(lastSyncTime AS TIMESTAMP) DESC NULLS LAST
        ) AS rn
    FROM
        datalake_google_admin_raw.cloud_identity_device_users
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_device,
    ds_user_email,
    ds_management_state,
    ds_password_state,
    ds_user_agent,
    ts_first_sync,
    ts_last_sync,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
