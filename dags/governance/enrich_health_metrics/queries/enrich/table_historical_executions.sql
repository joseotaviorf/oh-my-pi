WITH table_info AS (
    SELECT 
        table,
        dag,
        task,
        layer,
        TO_DATE(year::STRING || '-' || month::STRING || '-' || day::STRING) AS dt_executed
    FROM 
        datalake_dag_inventory_clean.table
),
all_table_executions AS (
    SELECT 
        table,
        dag,
        TRIM(REGEXP_REPLACE(owner,'(airflow|\,)','')) AS owner,
        task,
        layer,
        ts_event::TIMESTAMP,    
        dt_executed
    FROM table_info AS tb
    JOIN datalake_airflow.log AS lg
    ON 
        tb.task = lg.id_task
        AND DATE(lg.ts_executed) = DATE(tb.dt_executed - INTERVAL 1 DAY) 
        AND DATE(lg.ts_event) = tb.dt_executed

    WHERE
        event IN ('running', 'success')    
),
table_executions AS (
    SELECT
        al.table,
        al.dag,
        al.owner,
        al.task,
        al.layer,
        al.dt_executed,
        MIN(al.ts_event) AS ts_task_started,
        MAX(al.ts_event) AS ts_task_ended 
    FROM
        all_table_executions AS al
    JOIN
        datalake_health_metrics.dag_historical_executions AS de
    ON
        al.dag = de.dag_name
        AND al.dt_executed = de.dt_executed
        AND al.ts_event > de.ts_dag_started
        AND al.ts_event < de.ts_dag_ended
    GROUP BY
        1, 2, 3, 4, 5, 6
)
SELECT
    table AS table_name,
    dag AS dag_name,
    owner AS dag_owner,
    task,
    layer AS dag_layer,
    ts_task_started,
    ts_task_ended,
    DATEDIFF(MINUTE, ts_task_started, ts_task_ended) AS duration_in_minutes,
    dt_executed
FROM 
    table_executions