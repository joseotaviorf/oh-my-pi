WITH latest_snapshot AS (
    SELECT
        id_group,
        id_group_external,
        display_name,
        MAKE_DATE(year, month, day) AS dt_created,
        MAKE_DATE(year, month, day) AS dt_updated,
        CAST(NULL AS DATE) AS dt_deleted
    FROM
        datalake_databricks.daily_groups
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE
),
new_deletes AS (
    SELECT
        ug.id_group,
        ug.id_group_external,
        ug.display_name,
        ug.dt_created,
        ug.dt_updated,
        CURRENT_DATE AS dt_deleted
    FROM
        datalake_databricks.unique_groups AS ug
    LEFT JOIN
        latest_snapshot AS ls
            ON ug.id_group = ls.id_group
    WHERE
        ug.dt_deleted IS NULL -- Not marked as deleted yet
        AND ls.id_group IS NULL -- But not in the latest snapshot
)
SELECT
    id_group,
    id_group_external,
    display_name,
    dt_created,
    dt_updated,
    dt_deleted
FROM
    latest_snapshot
UNION ALL
SELECT
    id_group,
    id_group_external,
    display_name,
    dt_created,
    dt_updated,
    dt_deleted
FROM
    new_deletes