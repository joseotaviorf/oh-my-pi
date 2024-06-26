SELECT DISTINCT
    MD5(
      COALESCE(cluster_compute_type, 'N/A') 
      || COALESCE(execution_context, 'N/A') 
      || COALESCE(spark_version, 'N/A') 
      || COALESCE(runtime_engine, 'N/A')
    ) AS sk_cluster_config,
    cluster_compute_type,
    execution_context,
    spark_version,
    runtime_engine,
    NOW() AS ts_load
FROM
    datalake_databricks_usage_costs.usage_costs
