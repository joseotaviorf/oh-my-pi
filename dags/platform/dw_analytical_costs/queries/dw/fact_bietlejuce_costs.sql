SELECT
    MD5(id_dag || dt_execution) AS sk_snapshot,
    id_dag AS sk_dag,
    MD5(
      COALESCE(cluster_compute_type, 'N/A') 
      || COALESCE(execution_context, 'N/A') 
      || COALESCE(spark_version, 'N/A') 
      || COALESCE(runtime_engine, 'N/A')
    ) AS sk_cluster_config,
    COALESCE(CAST(REPLACE(SUBSTRING(dt_execution, 1, 10),'-','') AS BIGINT), -1) AS sk_execution_date,
    COALESCE(CAST(REPLACE(SUBSTRING(dt_spark_updated, 1, 10),'-','') AS BIGINT), -1) AS sk_spark_updated_date,
    cluster_name,
    job_name,
    SUM(dbus) OVER (PARTITION BY id_dag, dt_execution) AS dbus,
    SUM(price) OVER (PARTITION BY id_dag, dt_execution) AS price,
    daily_executions,
    spark_version_number,
    is_dag_builder_migrated,
    ts_bietlejuice_first_execution,
    ts_bietlejuice_last_execution,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_databricks_usage_costs.usage_costs
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}') 
    AND execution_context IN ("bietlejuice", "wonka dag")
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_dag, dt_execution ORDER BY ts_execution DESC) = 1
