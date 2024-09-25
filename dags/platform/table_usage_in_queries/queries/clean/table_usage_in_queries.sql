SELECT
    query_table_name,
    query_dag_name,
    query_layer,
    query_path,
    used_table,
    query_last_modified AS ts_query_last_modified,
    year,
    month,
    day
FROM
    datalake_databricks_raw.table_usage_in_queries
WHERE
    MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
