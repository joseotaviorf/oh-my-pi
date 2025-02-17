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
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"

