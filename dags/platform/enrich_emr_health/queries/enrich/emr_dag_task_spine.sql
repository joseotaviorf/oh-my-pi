-- ============================================================================
-- emr_dag_task_spine.sql
--
-- Bridge from EMR clusters to the Airflow tasks that ran on them. Grain:
--   (dt_step, id_emr_cluster, id_emr_step) — one row per EMR step task.
--
-- Steps are selected by operator: QuintoAndarEmrSubmitStepsOperator is exactly
-- the set of Airflow tasks submitted to an EMR cluster as a step. Selecting by
-- "every task except the lifecycle ones" is wrong — it sweeps in sensors,
-- short-circuits and non-EMR operators, and fact_emr_task_run then prorates
-- billed cluster cost to tasks that never touched the cluster.
--
-- Cluster identity comes from emr_instance_timeline (CUR + Airflow lifecycle).
-- Clusters without a resolved run_id are dropped: with no run there is no
-- defensible task set, and inventing one would misattribute cost.
--
-- A run can hold up to 6 concurrent clusters, and a task's cluster is not
-- recoverable from its task id. Each task is therefore assigned to exactly one
-- cluster of its run — preferring the cluster whose window contains the task,
-- then the nearest start. ROW_NUMBER enforces one row per task, so cost is
-- never multiplied across the run's clusters; a mis-pick moves cost between
-- clusters of the same run, leaving fact_emr_dag_run exact.
--
-- id_emr_step is a deterministic synthetic id. Real EMR step ids arrive on the
-- forward lane via EventBridge (`exact_event`); no EMR control-plane call and
-- no S3 log listing happens here.
-- ============================================================================
WITH clusters AS (
    SELECT
        id_emr_cluster,
        MAX(dag_id)                                        AS airflow_dag_id,
        MAX(run_id)                                        AS airflow_run_id,
        MIN(ts_cluster_started)                            AS ts_cluster_started,
        MAX(ts_cluster_ended)                              AS ts_cluster_ended
    FROM
        datalake_emr_health.emr_instance_timeline
    WHERE
        dt_cluster_run >= DATE('{load_start_date}')
        AND dt_cluster_run <  DATE('{load_end_date}')
        AND dag_id IS NOT NULL
        AND run_id IS NOT NULL
    GROUP BY
        id_emr_cluster
),
step_tasks AS (
    SELECT
        id_dag                                             AS airflow_dag_id,
        id_run                                             AS airflow_run_id,
        id_task                                            AS airflow_task_id,
        task_state,
        ts_started,
        ts_ended
    FROM
        datalake_airflow.task_instance
    WHERE
        operator = 'QuintoAndarEmrSubmitStepsOperator'
        AND (year * 100 + month) >= (
            YEAR(DATE_SUB(DATE('{load_start_date}'), 2)) * 100
            + MONTH(DATE_SUB(DATE('{load_start_date}'), 2))
        )
        AND (year * 100 + month) <= (
            YEAR(DATE_ADD(DATE('{load_end_date}'), 2)) * 100
            + MONTH(DATE_ADD(DATE('{load_end_date}'), 2))
        )
        AND COALESCE(DATE(ts_started), DATE(ts_executed), DATE(ts_queued))
            >= DATE_SUB(DATE('{load_start_date}'), 2)
        AND COALESCE(DATE(ts_started), DATE(ts_executed), DATE(ts_queued))
            <  DATE_ADD(DATE('{load_end_date}'), 2)
),
paired AS (
    SELECT
        t.airflow_dag_id,
        t.airflow_run_id,
        t.airflow_task_id,
        t.task_state,
        t.ts_started,
        t.ts_ended,
        c.id_emr_cluster,
        c.ts_cluster_started,
        c.ts_cluster_ended,
        ROW_NUMBER() OVER (
            PARTITION BY
                t.airflow_dag_id,
                t.airflow_run_id,
                t.airflow_task_id
            ORDER BY
                CASE
                    WHEN t.ts_started >= c.ts_cluster_started
                     AND t.ts_started <= COALESCE(
                             c.ts_cluster_ended,
                             t.ts_started
                         )
                        THEN 0
                    ELSE 1
                END,
                ABS(
                    UNIX_TIMESTAMP(t.ts_started)
                    - UNIX_TIMESTAMP(c.ts_cluster_started)
                ),
                c.id_emr_cluster
        )                                                  AS cluster_rank
    FROM
        step_tasks AS t
    INNER JOIN
        clusters AS c
            ON  c.airflow_dag_id = t.airflow_dag_id
            AND c.airflow_run_id = t.airflow_run_id
)
SELECT
    airflow_dag_id,
    airflow_run_id,
    airflow_task_id,
    id_emr_cluster,
    CONCAT(
        'synthetic-',
        SUBSTR(SHA2(CONCAT(id_emr_cluster, '|', airflow_task_id), 256), 1, 16)
    )                                                      AS id_emr_step,
    ts_started                                             AS ts_step_started,
    ts_ended                                               AS ts_step_ended,
    CASE LOWER(task_state)
        WHEN 'success'         THEN 'COMPLETED'
        WHEN 'failed'          THEN 'FAILED'
        WHEN 'upstream_failed' THEN 'CANCELLED'
        WHEN 'skipped'         THEN 'CANCELLED'
        ELSE 'UNKNOWN'
    END                                                    AS step_state,
    ts_cluster_started,
    ts_cluster_ended,
    'synthetic'                                            AS match_confidence,
    CURRENT_TIMESTAMP()                                    AS ts_load,
    DATE(COALESCE(ts_started, ts_cluster_started))         AS dt_step
FROM
    paired
WHERE
    cluster_rank = 1
    AND COALESCE(ts_started, ts_cluster_started) IS NOT NULL
