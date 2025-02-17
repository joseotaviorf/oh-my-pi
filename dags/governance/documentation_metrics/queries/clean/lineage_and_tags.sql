SELECT
    database_name,
    table_name,
    has_lineage,
    has_tags,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.lineage_and_tags
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"

