WITH latest_snapshot AS (
    SELECT
        id_user,
        email,
        is_active_user,
        is_active_employee,
        MAKE_DATE(year, month, day) AS dt_created,
        MAKE_DATE(year, month, day) AS dt_updated,
        CAST(NULL AS DATE) AS dt_deleted
    FROM
        datalake_databricks.daily_users
    WHERE
        -- We use current_date because the source is a snapshot. We can't process the history, so no point
        -- in using the execution date or load_start_date
        MAKE_DATE(year, month, DAY) = CURRENT_DATE
),
new_deletes AS (
    SELECT
        uu.id_user,
        uu.email,
        FALSE AS is_active_user,
        uu.is_active_employee,
        uu.dt_created,
        uu.dt_updated,
        CURRENT_DATE AS dt_deleted
    FROM
        datalake_databricks.unique_users AS uu
    LEFT JOIN
        latest_snapshot AS ls
            ON uu.id_user = ls.id_user
    WHERE
        uu.dt_deleted IS NULL -- Not marked as deleted yet
        AND ls.id_user IS NULL -- But not in the latest snapshot
)
SELECT
    id_user,
    email,
    is_active_user,
    is_active_employee,
    dt_created,
    dt_updated,
    dt_deleted
FROM
    latest_snapshot
UNION ALL
SELECT
    id_user,
    email,
    is_active_user,
    is_active_employee,
    dt_created,
    dt_updated,
    dt_deleted
FROM
    new_deletes
