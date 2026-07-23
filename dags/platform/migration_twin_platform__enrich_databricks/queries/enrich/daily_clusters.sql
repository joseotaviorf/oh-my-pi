WITH cluster_states AS (
    SELECT
        csf.cluster_id AS id_cluster,
        c.id_driver_instance_pool,
        c.id_worker_instance_pool,
        csf.cluster_name,
        c.bietlejuice_dag_name AS dag_name,
        c.driver_instance_pool_name,
        c.worker_instance_pool_name,
        csf.driver_node_type_id AS driver_node_type,
        csf.node_type_id AS node_type,
        csf.sku AS sku,
        csf.runtime_engine,
        c.spark_version,
        csf.total_dbu_cost,
        csf.total_compute_cost AS total_ec2_cost,
        csf.total_cost AS total_cost,
        csf.current_num_workers,
        csf.target_num_workers,
        csf.state,
        -- The field "uptime_in_state_S" exists in clusterstatefact. However, it takes into account future days, which we want to avoid.
        -- This is capping the uptime to the end of the day, or the end of the state, whichever comes first.
        (unix_seconds(LEAST(csf.timestamp_state_end, csf.state_start_date + INTERVAL '1' DAYS)) - unix_seconds(csf.timestamp_state_start)) AS uptime_in_state_S,
        csf.timestamp_state_start,
        csf.timestamp_state_end,
        ROW_NUMBER() OVER(PARTITION BY csf.cluster_id, csf.state_start_date ORDER BY csf.timestamp_state_start) AS state_row_number,
        csf.state_start_date AS dt_cluster_run
    FROM
        overwatch.clusterstatefact AS csf
    JOIN
        datalake_databricks.unique_clusters AS c
            ON csf.cluster_id = c.id_cluster
    WHERE
        csf.state_start_date BETWEEN "{load_start_date}" AND "{load_end_date}"
        AND csf.state != "TERMINATING"
),
clusters_aux AS (
    SELECT
        id_cluster,
        ANY_VALUE(id_driver_instance_pool) AS id_driver_instance_pool,
        ANY_VALUE(id_worker_instance_pool) AS id_worker_instance_pool,
        ANY_VALUE(cluster_name) AS cluster_name,
        ANY_VALUE(dag_name) AS dag_name,
        ANY_VALUE(driver_instance_pool_name) AS driver_instance_pool_name,
        ANY_VALUE(worker_instance_pool_name) AS worker_instance_pool_name,
        ANY_VALUE(driver_node_type) AS driver_node_type,
        ANY_VALUE(node_type) AS node_type,
        ANY_VALUE(sku) AS sku,
        ANY_VALUE(runtime_engine) AS runtime_engine,
        ANY_VALUE(spark_version) AS spark_version,
        SUM(total_dbu_cost) AS total_dbu_cost,
        SUM(total_ec2_cost) AS total_ec2_cost,
        SUM(total_cost) AS total_cost,
        SUM(IF(state IN ('STARTING', 'CREATING'), uptime_in_state_S, NULL)) AS total_seconds_in_starting_state,
        SUM(uptime_in_state_S) AS total_seconds_uptime,
        SUM(uptime_in_state_S * target_num_workers) AS total_worker_instance_usage_seconds,
        MIN(IF(state IN ('STARTING', 'CREATING'), state_row_number, NULL)) AS cluster_started_state_row_number,
        MIN(IF(state = 'INIT_SCRIPTS_STARTED', state_row_number, NULL)) AS init_scripts_started_state_row_number,
        MIN(IF(state = 'INIT_SCRIPTS_FINISHED', state_row_number, NULL)) AS init_scripts_finished_state_row_number,
        MIN(IF(state = 'RUNNING', state_row_number, NULL)) AS running_state_row_number,
        MIN(timestamp_state_start) AS ts_first_state_started,
        MIN(IF(state IN ('STARTING', 'CREATING'), timestamp_state_start, NULL)) AS ts_cluster_started,
        MIN(IF(state = 'INIT_SCRIPTS_STARTED', timestamp_state_start, NULL)) AS ts_init_scripts_started,
        MIN(IF(state = 'INIT_SCRIPTS_FINISHED', timestamp_state_start, NULL)) AS ts_init_scripts_finished,
        MIN(IF(state = 'RUNNING', timestamp_state_start, NULL)) AS ts_running_started,
        MAX(timestamp_state_end) AS ts_cluster_ended,
        dt_cluster_run
    FROM
        cluster_states
    GROUP BY
        id_cluster,
        dt_cluster_run
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
    CASE
        WHEN init_scripts_started_state_row_number = cluster_started_state_row_number + 1
          THEN DATE_DIFF(SECOND, ts_cluster_started, ts_init_scripts_started)
        ELSE NULL -- For edge cases in which the cluster started in the previous day, or init scripts were added later in the day
    END AS seconds_cluster_started_to_init_scripts_started,
    CASE
        WHEN init_scripts_finished_state_row_number = init_scripts_started_state_row_number + 1
          THEN DATE_DIFF(SECOND, ts_init_scripts_started, ts_init_scripts_finished)
        ELSE NULL -- For edge cases in which the cluster started in the previous day, or init scripts were added later in the day
    END  AS seconds_init_scripts_started_to_init_scripts_finished,
    CASE
        WHEN running_state_row_number = init_scripts_finished_state_row_number + 1
          THEN DATE_DIFF(SECOND, ts_init_scripts_finished, ts_running_started)
        ELSE NULL -- For edge cases in which the cluster started in the previous day, or init scripts were added later in the day
    END AS seconds_init_scripts_finished_to_running_started,
    CASE
        WHEN ts_running_started > ts_cluster_started
          THEN DATE_DIFF(SECOND, ts_cluster_started, ts_running_started)
        ELSE NULL -- For edge cases in which the cluster started in the previous day
    END AS seconds_total_startup_time,
    total_seconds_in_starting_state,
    total_seconds_uptime,
    total_worker_instance_usage_seconds,
    total_worker_instance_usage_seconds / total_seconds_uptime AS avg_target_num_workers,
    ROW_NUMBER() OVER(
        PARTITION BY
            dag_name, dt_cluster_run
        ORDER BY
            ts_cluster_started DESC
    ) = 1 AS is_last_of_day_for_dag,
    ts_init_scripts_started,
    ts_init_scripts_finished,
    ts_first_state_started,
    ts_cluster_started,
    ts_running_started,
    ts_cluster_ended,
    dt_cluster_run
FROM
    clusters_aux
