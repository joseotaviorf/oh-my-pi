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
    datalake_documentation_metrics_raw.categories_documentation
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"

