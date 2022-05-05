SELECT
    layer,
    database_name,
    table_name,
    column_name,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.columns_metastore
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
