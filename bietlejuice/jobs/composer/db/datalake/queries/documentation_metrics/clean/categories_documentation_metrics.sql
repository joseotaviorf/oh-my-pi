SELECT
    layer,
    database_name,
    table_name,
    column_name,
    value,
    has_description,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.categories_documentation_metrics
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
