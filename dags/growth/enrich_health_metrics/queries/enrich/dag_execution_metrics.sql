WITH dag_layer AS (
    SELECT DISTINCT 
        dag, 
        CASE 
            WHEN CONCAT_WS('|', ARRAY_SORT(ARRAY_DISTINCT(ARRAY_AGG(layer)))) LIKE 'clean%' THEN 'clean|raw'
            ELSE CONCAT_WS('|', ARRAY_SORT(ARRAY_DISTINCT(ARRAY_AGG(layer))))
        END AS layer
    FROM datalake_dag_inventory_clean.table
    GROUP BY 1
),
dag_names AS (
    SELECT DISTINCT 
        id_dag, 
        owners AS dag_owner, 
        layer AS dag_layer,
        DATE(adt.date) AS dt_executed
    FROM datalake_composer_clean.dag AS dag
    LEFT JOIN dag_layer AS layer
    ON dag.id_dag = layer.dag
    CROSS JOIN datalake_quintoandar.aux_date AS adt
    WHERE
        dag.is_paused = FALSE
        AND adt.date >= DATE('2021-01-01') and adt.date <= current_date()
),
execution_logs AS (
    SELECT
        dag.id_dag,
        dag.dag_owner,
        dag.dag_layer,
        dag.dt_executed,
        MIN(IF(log.event = 'running' AND log.id_task = 'create-cluster', 
                log.id_log, 
                NULL
              )) AS id_log_first_task,
        MIN(IF(log.event = 'success' AND log.id_task = 'terminate-cluster', 
                log.id_log, 
                NULL
              )) AS id_log_last_task
    FROM 
        dag_names AS dag
    INNER JOIN 
        datalake_composer_clean.log log
    ON 
        log.id_dag = dag.id_dag
        AND DATE(log.ts_executed) = dag.dt_executed - INTERVAL 1 day
        AND DATE(log.ts_event) = dag.dt_executed
    WHERE 
        log.event IN ('success','running')
    GROUP BY 1,2,3,4
),
execution_metrics AS (
    SELECT
        exec.id_dag AS dag_name,
        exec.dag_owner,
        exec.dag_layer,
        exec.dt_executed,
        log_started.ts_event AS ts_dag_started,
        log_last_task.ts_event AS ts_dag_ended,
        DATEDIFF(MINUTE, log_started.ts_event, log_last_task.ts_event) AS duration_in_minutes

    FROM 
        execution_logs AS exec
    JOIN
        datalake_composer_clean.log log_started
    ON
        log_started.id_dag = exec.id_dag
        AND log_started.id_log = exec.id_log_first_task
        AND log_started.event = 'running'
        --Due to new composer instance
        AND DATE(log_started.ts_event) > DATE(exec.dt_executed - INTERVAL 2 day)
    JOIN
        datalake_composer_clean.log log_last_task
    ON
        log_last_task.id_dag = exec.id_dag
        AND log_last_task.id_log = exec.id_log_last_task
        AND log_last_task.event = 'success'
        --Due to new composer instance
        AND DATE(log_last_task.ts_event) > DATE(exec.dt_executed - INTERVAL 2 day)
),
historical_execution_metrics AS (
    SELECT 
        dag_name,
        dag_owner,
        MEDIAN( DATE_FORMAT(ts_dag_started,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_started,        
        MEDIAN( DATE_FORMAT(ts_dag_ended,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_ended,
        MEDIAN(duration_in_minutes) AS duration_median_in_minutes
    FROM 
        execution_metrics AS em
    JOIN
        datalake_gsheets_clean.reference_sla_days AS rs
    ON
        DATE(em.dt_executed) = DATE(rs.dt_reference_date)
    GROUP BY
        1, 2
)
SELECT
    em.dag_name,
    em.dag_owner,
    em.dag_layer,
    em.dt_executed,
    em.ts_dag_started,
    em.ts_dag_ended,
    em.duration_in_minutes,
    he.ts_median_started,
    he.ts_median_ended,
    he.duration_median_in_minutes
FROM 
    execution_metrics AS em
JOIN 
    historical_execution_metrics AS he    
ON
    em.dag_name = he.dag_name
    AND em.dag_owner = he.dag_owner