SELECT
    database_name,
    table_name,
    table_description,
    owner,
    column_name,
    column_description,
    joins_with_column,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.columns_documentation
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
