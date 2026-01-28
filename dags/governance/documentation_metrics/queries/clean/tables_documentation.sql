SELECT
    database_name,
    table_name,
    domain,
    owner,
    table_description,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.tables_documentation
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"