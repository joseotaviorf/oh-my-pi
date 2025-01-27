SELECT
    layer,
    database_name,
    table_name,
    column_name,
    value,
    has_description,
    date(format_string('%d-%d-%d',year, month, day)) as dt_ingested,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_clean.categories_documentation
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
