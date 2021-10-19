SELECT
    layer,
    database_name,
    table_name,
    column_name,
    has_description,
    has_joins_with_column,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.columns_documentation_metrics
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
