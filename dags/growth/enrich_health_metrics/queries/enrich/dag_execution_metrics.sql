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
),
historical_execution_metrics AS (
    SELECT 
        em.dag_name,
        em.dag_owner,
        MEDIAN( DATE_FORMAT(ts_dag_started,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_started,        
        MEDIAN( DATE_FORMAT(ts_dag_ended,'HH:mm:ss')::TIMESTAMP::BIGINT )::TIMESTAMP AS ts_median_ended,
        MEDIAN(duration_in_minutes) AS duration_median_in_minutes
    FROM 
        datalake_health_metrics.dag_historical_executions AS em
    JOIN
        top_reference_sla_days AS rs
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