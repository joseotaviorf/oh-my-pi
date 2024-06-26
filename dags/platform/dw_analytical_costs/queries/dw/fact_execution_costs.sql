SELECT
    id_cluster AS sk_cluster,
    MD5(
      COALESCE(cluster_compute_type, 'N/A') 
      || COALESCE(execution_context, 'N/A') 
      || COALESCE(spark_version, 'N/A') 
      || COALESCE(runtime_engine, 'N/A')
    ) AS sk_cluster_config,
    COALESCE(CAST(REPLACE(SUBSTRING(dt_execution, 1, 10),'-','') AS BIGINT), -1) AS sk_execution_date,
    cluster_name,
    dbus,
    price,
    spark_version_number,
    ts_execution,
    year,
    month,
    day,
    NOW() AS ts_load
FROM
    datalake_databricks_usage_costs.usage_costs
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}') 
    AND execution_context = "adhoc execution"
