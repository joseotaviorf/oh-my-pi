WITH clusters_aux AS (
    SELECT
        csf.cluster_id AS id_cluster,
        ANY_VALUE(c.id_driver_instance_pool) AS id_driver_instance_pool,
        ANY_VALUE(c.id_worker_instance_pool) AS id_worker_instance_pool,
        ANY_VALUE(csf.cluster_name) AS cluster_name,
        ANY_VALUE(c.bietlejuice_dag_name) AS dag_name,
        ANY_VALUE(c.driver_instance_pool_name) AS driver_instance_pool_name,
        ANY_VALUE(c.worker_instance_pool_name) AS worker_instance_pool_name,
        ANY_VALUE(csf.driver_node_type_id) AS driver_node_type,
        ANY_VALUE(csf.node_type_id) AS node_type,
        ANY_VALUE(csf.sku) AS sku,
        ANY_VALUE(csf.runtime_engine) AS runtime_engine,
        ANY_VALUE(c.spark_version) AS spark_version,
        SUM(csf.total_dbu_cost) AS total_dbu_cost,
        SUM(csf.total_compute_cost) AS total_ec2_cost,
        SUM(csf.total_cost) AS total_cost,
        MIN(timestamp_state_start) AS ts_cluster_started,
        MIN(IF(csf.state = 'INIT_SCRIPTS_STARTED', timestamp_state_start, NULL)) AS ts_init_scripts_started,
        MIN(IF(csf.state = 'INIT_SCRIPTS_FINISHED', timestamp_state_start, NULL)) AS ts_init_scripts_finished,
        MIN(IF(csf.state = 'RUNNING', timestamp_state_start, NULL)) AS ts_running_started,
        MAX(timestamp_state_end) AS ts_cluster_ended,
        csf.state_start_date AS dt_cluster_run
    FROM
        overwatch.clusterstatefact AS csf
    JOIN
        datalake_databricks.unique_clusters AS c
            ON csf.cluster_id = c.id_cluster
    WHERE
        csf.state_start_date BETWEEN "{load_start_date}" AND "{load_end_date}"
        AND csf.state != "TERMINATING"
    GROUP BY
        csf.cluster_id,
        csf.state_start_date
)
SELECT
    id_cluster,
    id_driver_instance_pool,
    id_worker_instance_pool,
    cluster_name,
    dag_name,
    driver_instance_pool_name,
    worker_instance_pool_name,
    driver_node_type,
    node_type,
    sku,
    runtime_engine,
    spark_version,
    total_dbu_cost,
    total_ec2_cost,
    total_cost,
    DATE_DIFF(SECOND, ts_cluster_started, ts_init_scripts_started) AS seconds_cluster_started_to_init_scripts_started,
    DATE_DIFF(SECOND, ts_init_scripts_started, ts_init_scripts_finished) AS seconds_init_scripts_started_to_init_scripts_finished,
    DATE_DIFF(SECOND, ts_init_scripts_finished, ts_running_started) AS seconds_init_scripts_finished_to_running_started,
    DATE_DIFF(SECOND, ts_cluster_started, ts_running_started) AS seconds_total_startup_time,
    ROW_NUMBER() OVER(
        PARTITION BY
            dag_name, dt_cluster_run
        ORDER BY
            ts_cluster_started DESC
    ) = 1 AS is_last_of_day_for_dag,
    ts_init_scripts_started,
    ts_init_scripts_finished,
    ts_running_started,
    ts_cluster_started,
    ts_cluster_ended,
    dt_cluster_run
FROM
    clusters_aux