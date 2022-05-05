WITH table_metastore AS (
    SELECT
        layer,
        database_name,
        table_name,
        year,
        month,
        day
    FROM
        datalake_documentation_metrics_clean.columns_metastore
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY
        layer,
        database_name,
        table_name,
        year,
        month,
        day
), table_documentation AS (
    SELECT
        database_name,
        table_name,
        table_description,
        owner
    FROM
        datalake_documentation_metrics_clean.columns_documentation
    WHERE
        year = {year}
        AND month = {month}
        AND day = {day}
    GROUP BY
        database_name,
        table_name,
        table_description,
        owner
)
SELECT
    ms.layer,
    ms.database_name,
    ms.table_name,
    COALESCE(doc.owner != '', FALSE) AS has_owner,
    COALESCE(doc.table_description != '', FALSE) AS has_description,
    ms.year,
    ms.month,
    ms.day
FROM
    table_metastore AS ms
LEFT JOIN
    table_documentation AS doc
        ON ms.database_name = doc.database_name
        AND ms.table_name = doc.table_name