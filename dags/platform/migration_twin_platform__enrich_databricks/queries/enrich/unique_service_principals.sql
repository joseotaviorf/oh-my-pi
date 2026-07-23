WITH latest_snapshot AS (
    SELECT
        id_service_principal,
        id_service_principal_external,
        display_name,
        application_id,
        is_active,
        MAKE_DATE(year, month, day) AS dt_created,
        MAKE_DATE(year, month, day) AS dt_updated,
        NULL::DATE AS dt_deleted
    FROM
        datalake_databricks.daily_service_principals
    WHERE
        MAKE_DATE(year, month, day) = CURRENT_DATE
),
new_deletes AS (
    SELECT
        usp.id_service_principal,
        usp.id_service_principal_external,
        usp.display_name,
        usp.application_id,
        usp.is_active,
        usp.dt_created,
        usp.dt_updated,
        CURRENT_DATE AS dt_deleted
    FROM
        datalake_databricks.unique_service_principals AS usp
    LEFT JOIN
        latest_snapshot AS ls
            ON usp.id_service_principal = ls.id_service_principal
    WHERE
        usp.dt_deleted IS NULL -- Not marked as deleted yet
        AND ls.id_service_principal IS NULL -- But not in the latest snapshot
)
SELECT
    id_service_principal,
    id_service_principal_external,
    display_name,
    application_id,
    is_active,
    dt_created,
    dt_updated,
    dt_deleted
FROM
    latest_snapshot
UNION ALL
SELECT
    id_service_principal,
    id_service_principal_external,
    display_name,
    application_id,
    is_active,
    dt_created,
    dt_updated,
    dt_deleted
FROM
    new_deletes
