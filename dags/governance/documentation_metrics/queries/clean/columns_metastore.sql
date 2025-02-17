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
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"

