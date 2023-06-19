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
        dt_executed >= CURRENT_DATE() - INTERVAL '60' DAY
        AND dag_name NOT IN (SELECT dag FROM datalake_gsheets_clean.dags_sla_exclusion_list)
        AND dag_owner NOT IN ('MLOps','Data Governance','Data Primitives')
),
reference_sla_days AS (
    SELECT
        dag_owner,  
        dt_executed,
        COUNT( DISTINCT dag_name ) AS total_dags,
        COUNT( DISTINCT is_sla_dag ) AS dags_sla_ok
    FROM 
        execution_metrics_last_60_days
    GROUP BY 
        1, 2
    HAVING
        total_dags = dags_sla_ok
),
top_reference_sla_days AS (
    SELECT 
        dag_owner,
        dt_executed,
        RANK() OVER(PARTITION BY dag_owner ORDER BY dt_executed) AS rank
    FROM
        reference_sla_days
    QUALIFY 
        rank <= 20
)
SELECT 
    dag_owner,
    dt_executed
FROM
    top_reference_sla_days