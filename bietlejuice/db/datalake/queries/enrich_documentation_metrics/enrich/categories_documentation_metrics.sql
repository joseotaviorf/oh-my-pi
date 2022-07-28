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
    datalake_documentation_metrics_clean.categories_documentation
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
