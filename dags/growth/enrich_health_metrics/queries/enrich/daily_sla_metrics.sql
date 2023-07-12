WITH execution_metrics_last_60_days AS (
    SELECT 
        TRIM(REGEXP_REPLACE(dag_owner,'(airflow|\,)','')) AS dag_owner,
        dag_name,
        dt_executed,
        CASE WHEN 
            (dag_name NOT LIKE '%dw_datamarts%' AND ts_dag_ended - INTERVAL '3' HOUR > dt_executed::TIMESTAMP + INTERVAL '480' MINUTE)
            OR (dag_name LIKE '%dw_datamarts%' AND ts_dag_ended - INTERVAL '3' HOUR > dt_executed::TIMESTAMP + INTERVAL '630' MINUTE)
            THEN NULL ELSE dag_name
         END AS is_sla_dag
    FROM 
        datalake_health_metrics.dag_historical_executions
    WHERE 
        dag_name NOT IN (SELECT dag FROM datalake_gsheets_clean.dags_sla_exclusion_list)
        AND dag_owner NOT IN ('MLOps','Data Governance','Data Primitives')
)
SELECT
    dag_owner,  
    dt_executed,
    COUNT( DISTINCT dag_name ) AS total_dags,
    COUNT( DISTINCT is_sla_dag ) AS dags_sla_ok,
    ROUND( COUNT( DISTINCT is_sla_dag ) / COUNT( DISTINCT dag_name ), 2) AS ratio_sla_ok
FROM 
    execution_metrics_last_60_days
GROUP BY 
    1, 2