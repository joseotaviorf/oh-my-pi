SELECT
    layer,
    dag_name,
    database_name,
    has_lineage_from_product,
    owner,
    year,
    month,
    day
FROM
    datalake_documentation_metrics_raw.dag_metadata
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"

