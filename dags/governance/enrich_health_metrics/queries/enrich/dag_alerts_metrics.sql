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
dags AS (
    SELECT DISTINCT 
        id_dag AS dag_name, 
        REGEXP_REPLACE(owners,'(airflow|\,)','') AS dag_owner,
        layer AS dag_layer,
        DATE(adt.date) AS dt_executed
    FROM datalake_airflow.dag AS dag
    LEFT JOIN dag_layer AS layer
    ON dag.id_dag = layer.dag
    CROSS JOIN datalake_quintoandar.aux_date AS adt
    WHERE
        dag.is_paused = FALSE
        AND adt.date >= DATE('2021-01-01') and adt.date <= current_date()
),
airflow_failed_tasks AS (
    SELECT
        id_dag AS dag_name,
        DATE(ts_executed) AS dt_executed,
        COUNT(DISTINCT id_fail) AS qt_failed_airflow_tasks
    FROM 
        datalake_airflow.task_fail
    GROUP BY
        1, 2
),
opsgenie_alerts AS (
    SELECT 
        dag_name,
        DATE(a.ts_created) AS dt_executed,
        COUNT(DISTINCT a.id) AS qt_opsgenie_alerts,
        COUNT( DISTINCT 
            CASE
                WHEN DAYOFWEEK(a.ts_created) IN (2,3,4,5,6) AND HOUR(a.ts_created) <= 12 AND is_call_notification_made = true THEN a.id
                WHEN DAYOFWEEK(a.ts_created) IN (1,7) AND HOUR(a.ts_created) >= 12 AND HOUR(a.ts_created) <= 15 AND is_call_notification_made = true THEN a.id
                ELSE NULL
            END
        ) AS qt_opsgenie_on_call_alerts        
    FROM
        datalake_opsgenie_clean.alerts AS a
    LEFT JOIN
        datalake_opsgenie_clean.logs AS l
    ON
        a.id = l.id
        AND a.year = l.year
        AND a.month = l.month
        AND a.day = l.day
    GROUP BY 
        1, 2
),
databricks_cluster_alerts AS (
    SELECT
        'bietlejuice.' || dag_name AS dag_name,
        DATE(ts_alert) AS dt_executed,
        SUM( CASE WHEN alert_name LIKE '%cpu-alert%' THEN 1 ELSE 0 END ) AS qt_cluster_cpu_alerts,
        SUM( CASE WHEN alert_name LIKE '%memory-swap-alert%' THEN 1 ELSE 0 END ) AS qt_cluster_memory_swap_alerts
    FROM 
        datalake_alert_manager_clean.alerts_databricks_cluster
    WHERE 
        message IS NOT NULL
    GROUP BY
        1, 2
),
dei_incidents AS (
    SELECT 
        REGEXP_EXTRACT(summary,'bietlejuice.[a-zA-Z0-9\_\-]+',0) AS dag_name,
        DATE(ts_created) AS dt_executed,
        COUNT(*) AS qt_dei_incidents
    FROM datalake_jira.issues
    WHERE 
        project_name LIKE 'Data Engineering Incidents'
        AND summary LIKE '%bietlejuice.%'
    GROUP BY
        1, 2
),
data_quality_fails AS (
    SELECT
        dag AS dag_name,
        DATE(ts_execution_utc) AS dt_executed,
        COUNT( DISTINCT CASE WHEN suite_result = 'error' THEN suite_name ELSE NULL END ) AS qt_failed_data_quality_tests
    FROM 
        datalake_inmetro_clean.data_validations AS dv
    JOIN 
        datalake_dag_inventory_clean.table AS tb
    ON 
        dv.database || '.' || dv.table = tb.table
    WHERE 
        repo = 'bietlejuice'
    GROUP BY 
        1, 2    
)
SELECT
	dg.dag_name,
    dg.dag_owner,
	dg.dag_layer,
	dg.dt_executed,
	qt_failed_airflow_tasks,
	qt_opsgenie_alerts,
    qt_opsgenie_on_call_alerts,
	qt_cluster_cpu_alerts,
	qt_cluster_memory_swap_alerts,
	qt_dei_incidents,
	qt_failed_data_quality_tests
FROM
	dags AS dg
LEFT JOIN
	airflow_failed_tasks AS af
ON
	dg.dag_name = af.dag_name
	AND dg.dt_executed = af.dt_executed
LEFT JOIN
	opsgenie_alerts AS oa
ON
	dg.dag_name = oa.dag_name
	AND dg.dt_executed = oa.dt_executed
LEFT JOIN
	databricks_cluster_alerts AS dc
ON
	dg.dag_name = dc.dag_name
	AND dg.dt_executed = dc.dt_executed
LEFT JOIN
	dei_incidents AS di
ON
	dg.dag_name = di.dag_name
	AND dg.dt_executed = di.dt_executed
LEFT JOIN
	data_quality_fails AS dq
ON
	dg.dag_name = dq.dag_name
	AND dg.dt_executed = dq.dt_executed		