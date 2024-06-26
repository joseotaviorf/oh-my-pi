SELECT
    MD5(id_job || dt_execution) AS sk_snapshot,
    id_job AS sk_job,
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
    SUM(dbus) OVER (PARTITION BY id_job, dt_execution) AS dbus,
    SUM(price) OVER (PARTITION BY id_job, dt_execution) AS price,
    daily_executions,
    spark_version_number,
    ts_job_first_execution,
    ts_job_last_execution,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_databricks_usage_costs.usage_costs
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND execution_context IN ("job", "wonka job")
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id_job, dt_execution ORDER BY ts_execution DESC) = 1
