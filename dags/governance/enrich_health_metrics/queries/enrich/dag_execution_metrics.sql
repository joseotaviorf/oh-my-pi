WITH historical_execution_metrics AS (
    SELECT 
        em.dag_name,
        em.dag_owner,
        MEDIAN( DATE_FORMAT(ts_dag_started,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_started,        
        MEDIAN( DATE_FORMAT(ts_dag_ended,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_ended,
        MEDIAN(duration_in_minutes) AS duration_median_in_minutes
    FROM 
        datalake_health_metrics.dag_historical_executions AS em
    JOIN
        datalake_health_metrics.top_reference_sla_days AS rs
    ON
        em.dag_owner = rs.dag_owner
        AND em.dt_executed = rs.dt_executed
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
    datalake_health_metrics.dag_historical_executions AS em
LEFT JOIN 
    historical_execution_metrics AS he    
ON
    em.dag_name = he.dag_name
    AND em.dag_owner = he.dag_owner