SELECT
    layer,
    database_name,
    table_name,
    has_description,
    has_owner,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.tables_documentation_metrics
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
