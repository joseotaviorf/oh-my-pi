WITH historical_execution_metrics AS (
    SELECT
        em.table_name,
        em.dag_owner,
        MEDIAN( DATE_FORMAT(ts_task_started,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_started,        
        MEDIAN( DATE_FORMAT(ts_task_ended,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_ended,
        MEDIAN(duration_in_minutes) AS duration_median_in_minutes
    FROM 
        datalake_health_metrics.table_historical_executions AS em
    JOIN
        datalake_health_metrics.top_reference_sla_days AS rs
    ON
        em.dag_owner = rs.dag_owner
        AND em.dt_executed = rs.dt_executed
    GROUP BY
        1, 2
)
SELECT
    em.table_name,
    em.dag_name,
    em.dag_owner,
    em.dag_layer,
    em.task,
    em.dt_executed,
    em.ts_task_started,
    em.ts_task_ended,
    em.duration_in_minutes,
    he.ts_median_started,
    he.ts_median_ended,
    he.duration_median_in_minutes
FROM 
    datalake_health_metrics.table_historical_executions AS em
LEFT JOIN 
    historical_execution_metrics AS he    
ON
    em.table_name = he.table_name
    AND em.dag_owner = he.dag_owner