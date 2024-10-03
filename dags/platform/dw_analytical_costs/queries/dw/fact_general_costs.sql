SELECT
    sk_snapshot,
    sk_dag,
    sk_line,
    NULL AS sk_cluster,
    NULL AS sk_job,
    sk_cluster_config,
    sk_execution_date,
    sk_spark_updated_date,
    cluster_name,
    job_name,
    dbus,
    price,
    daily_executions,
    spark_version_number,
    is_dag_builder_migrated,
    ts_bietlejuice_first_execution AS ts_first_execution,
    ts_bietlejuice_last_execution AS ts_last_execution,
    ts_bietlejuice_first_execution AS ts_execution,
    year,
    month,
    day
FROM
    dw_analytical_costs.fact_bietlejuice_costs
UNION ALL
SELECT
    sk_snapshot,
    NULL AS sk_dag,
    NULL AS sk_line,
    sk_cluster,
    NULL AS sk_job,
    sk_cluster_config,
    sk_execution_date,
    NULL AS sk_spark_updated_date,
    cluster_name,
    NULL AS job_name,
    dbus,
    price,
    NULL AS daily_executions,
    spark_version_number,
    NULL AS is_dag_builder_migrated,
    NULL AS ts_first_execution,
    NULL AS ts_last_execution,
    ts_execution,
    year,
    month,
    day
FROM
    dw_analytical_costs.fact_execution_costs
UNION ALL
SELECT
    sk_snapshot,
    NULL AS sk_dag,
    NULL AS sk_line,
    NULL AS sk_cluster,
    sk_job,
    sk_cluster_config,
    sk_execution_date,
    sk_spark_updated_date,
    cluster_name,
    job_name,
    dbus,
    price,
    daily_executions,
    spark_version_number,
    NULL AS is_dag_builder_migrated,
    ts_job_first_execution AS ts_first_execution,
    ts_job_last_execution AS ts_last_execution,
    ts_job_first_execution AS ts_execution,
    year,
    month,
    day
FROM
    dw_analytical_costs.fact_job_costs
