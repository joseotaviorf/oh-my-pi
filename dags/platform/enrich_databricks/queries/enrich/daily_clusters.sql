WITH clusters_aux AS (
    SELECT
        csf.cluster_id AS id_cluster,
        ANY_VALUE(csf.cluster_name) AS cluster_name,
        ANY_VALUE(CASE
            WHEN csf.cluster_name LIKE '%bietlejuice%'
              THEN REPLACE(
                  REGEXP_REPLACE(
                      REGEXP_REPLACE(csf.cluster_name, '.+-bietlejuice', 'bietlejuice'),
                      '(?:_mediator|_scheduled).+', ''
                  ), '-', '.'
              )
        END) AS dag_name,
        ANY_VALUE(csf.driver_node_type_id) AS driver_node_type,
        ANY_VALUE(csf.node_type_id) AS node_type,
        ANY_VALUE(csf.sku) AS sku,
        ANY_VALUE(csf.runtime_engine) AS runtime_engine,
        ANY_VALUE(c.spark_version) AS spark_version,
        SUM(csf.total_dbu_cost) AS total_dbu_cost,
        SUM(csf.total_compute_cost) AS total_ec2_cost,
        SUM(csf.total_cost) AS total_cost,
        MIN(timestamp_state_start) AS ts_cluster_started,
        MAX(timestamp_state_end) AS ts_cluster_ended,
        csf.state_start_date AS dt_cluster_run
    FROM
        overwatch.clusterstatefact AS csf
    JOIN
        overwatch.`cluster` AS c
            ON csf.cluster_id = c.cluster_id
    WHERE
        csf.state_start_date BETWEEN "{load_start_date}" AND "{load_end_date}"
        AND csf.state != "TERMINATING"
    GROUP BY
        csf.cluster_id,
        csf.state_start_date
)
SELECT
    id_cluster,
    cluster_name,
    dag_name,
    driver_node_type,
    node_type,
    sku,
    runtime_engine,
    spark_version,
    total_dbu_cost,
    total_ec2_cost,
    total_cost,
    ROW_NUMBER() OVER(
        PARTITION BY
            dag_name, dt_cluster_run
        ORDER BY
            ts_cluster_started DESC
    ) = 1 AS is_last_of_day_for_dag,
    ts_cluster_started,
    ts_cluster_ended,
    dt_cluster_run
FROM
    clusters_aux