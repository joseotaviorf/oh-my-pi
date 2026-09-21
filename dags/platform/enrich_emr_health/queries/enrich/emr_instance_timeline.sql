-- ============================================================================
-- emr_instance_timeline.sql
--
-- Per-instance timeline for Airflow-orchestrated EMR clusters. Grain:
--   (dt_cluster_run, id_emr_cluster, id_ec2_instance).
--
-- Identity and hours come from datalake_aws_billed_cost.daily_resource_billed_cost
-- (CUR). Cluster identity (cluster_name, run_id, dag_id, lifecycle timestamps)
-- is resolved events-first from EventBridge (datalake_emr_events_clean.events),
-- which carries the exact cluster name `{{dag_id}}_{{run_id}}` (primary >= 2026-08-28).
-- run_id is the cluster name minus the `{{dag_id}}_` prefix (dag_id from the CUR tag),
-- so custom run_ids (`val__…`, `emr_promo__…`) resolve too; when the tag is absent
-- (before 2026-09-01) the standard Airflow run-type marker locates the split.
--
-- For pre-event clusters (before 2026-08-28), identity falls back to an hour-bucket
-- heuristic against datalake_airflow.task_instance create/terminate tasks.
-- A create task anchors to the cluster's first billed hour (and spill hour if minute >= 45).
-- A cluster keeps run_id only when candidates resolve to a single run; ambiguous
-- clusters leave run_id as NULL. run_match records the resolution method
-- ('event', 'resolved', 'ambiguous', 'no_candidate').
--
-- Identity window scans load_start - 7d .. load_end + 2d so clusters starting
-- earlier keep their true first billed hour across daily runs.
--
-- Restricted to the EMR account (206390561754).
-- ============================================================================
WITH billed_window AS (
    SELECT
        dt_usage,
        resource_kind,
        id_resource,
        id_emr_cluster,
        tag_dag_id,
        instance_role,
        market,
        instance_type,
        usage_hours,
        ts_first_usage,
        ts_last_usage,
        tag_provisioner,
        tag_owner,
        tag_environment,
        tag_cost_center,
        tag_ecosystem,
        tag_data_classification,
        tag_sensitive_data
    FROM
        datalake_aws_billed_cost.daily_resource_billed_cost
    WHERE
        dt_usage >= DATE_SUB(DATE('{load_start_date}'), 7)
        AND dt_usage <  DATE_ADD(DATE('{load_end_date}'), 2)
        AND id_aws_account = '206390561754'
        AND (
                tag_provisioner = 'emr'
             OR id_emr_cluster IS NOT NULL
        )
),
billed AS (
    SELECT
        dt_usage,
        resource_kind,
        id_resource,
        id_emr_cluster,
        tag_dag_id,
        instance_role,
        market,
        instance_type,
        usage_hours,
        ts_first_usage,
        ts_last_usage,
        tag_provisioner,
        tag_owner,
        tag_environment,
        tag_cost_center,
        tag_ecosystem,
        tag_data_classification,
        tag_sensitive_data
    FROM
        billed_window
    WHERE
        dt_usage >= DATE('{load_start_date}')
        AND dt_usage <  DATE('{load_end_date}')
),
ec2 AS (
    SELECT
        id_emr_cluster,
        id_resource                                          AS id_ec2_instance,
        tag_dag_id,
        CASE
            WHEN UPPER(instance_role) IN ('MASTER', 'CORE', 'TASK')
                THEN UPPER(instance_role)
            ELSE 'UNKNOWN'
        END                                                  AS instance_role,
        CASE
            WHEN market IN ('spot', 'on_demand') THEN market
            ELSE 'on_demand'
        END                                                  AS market,
        instance_type,
        usage_hours                                          AS instance_hours_in_day,
        ts_first_usage,
        ts_last_usage,
        tag_provisioner,
        tag_owner,
        tag_environment,
        tag_cost_center,
        tag_ecosystem,
        tag_data_classification,
        tag_sensitive_data,
        dt_usage                                             AS dt_cluster_run
    FROM
        billed
    WHERE
        resource_kind = 'ec2_instance'
        AND id_emr_cluster IS NOT NULL
        AND id_resource IS NOT NULL
),
ebs_by_cluster_day AS (
    SELECT
        id_emr_cluster,
        dt_usage                                             AS dt_cluster_run,
        COLLECT_SET(id_resource)                             AS ebs_volume_ids
    FROM
        billed
    WHERE
        resource_kind = 'ebs_volume'
        AND id_emr_cluster IS NOT NULL
        AND id_resource IS NOT NULL
    GROUP BY
        id_emr_cluster,
        dt_usage
),
cluster_window AS (
    SELECT
        id_emr_cluster,
        MAX(tag_dag_id)                                      AS tag_dag_id,
        MAX(tag_provisioner)                                 AS tag_provisioner,
        MAX(tag_owner)                                       AS tag_owner,
        MAX(tag_environment)                                 AS tag_environment,
        MAX(tag_cost_center)                                 AS tag_cost_center,
        MAX(tag_ecosystem)                                   AS tag_ecosystem,
        MAX(tag_data_classification)                         AS tag_data_classification,
        MAX(tag_sensitive_data)                              AS tag_sensitive_data,
        MIN(ts_first_usage)                                  AS ts_first_usage,
        MAX(ts_last_usage)                                   AS ts_last_usage
    FROM
        billed_window
    WHERE
        resource_kind = 'ec2_instance'
        AND id_emr_cluster IS NOT NULL
        AND id_resource IS NOT NULL
    GROUP BY
        id_emr_cluster
),
airflow_lifecycle AS (
    SELECT
        id_task,
        id_dag,
        id_run,
        operator,
        ts_started,
        ts_ended
    FROM
        datalake_airflow.task_instance
    WHERE
        operator IN (
            'QuintoAndarEmrCreateClusterOperator',
            'QuintoAndarEmrTerminateClusterOperator'
        )
        AND (year * 100 + month) >= (
            YEAR(DATE_SUB(DATE('{load_start_date}'), 7)) * 100
            + MONTH(DATE_SUB(DATE('{load_start_date}'), 7))
        )
        AND (year * 100 + month) <= (
            YEAR(DATE_ADD(DATE('{load_end_date}'), 2)) * 100
            + MONTH(DATE_ADD(DATE('{load_end_date}'), 2))
        )
        AND COALESCE(DATE(ts_started), DATE(ts_executed), DATE(ts_queued))
            >= DATE_SUB(DATE('{load_start_date}'), 7)
        AND COALESCE(DATE(ts_started), DATE(ts_executed), DATE(ts_queued))
            <  DATE_ADD(DATE('{load_end_date}'), 2)
),
-- Create and terminate tasks pair inside a run by their task-id suffix
-- (execute-job-cluster-N <-> terminate-emr-cluster-N, N omitted for the first).
-- Measured: 20,733 of 20,784 creates over 7 days find their terminate this way.
lifecycle_task AS (
    SELECT
        id_dag,
        id_run,
        operator,
        COALESCE(
            NULLIF(REGEXP_EXTRACT(id_task, '-([0-9]+)$', 1), ''),
            '1'
        )                                                    AS cluster_slot,
        ts_started,
        ts_ended
    FROM
        airflow_lifecycle
),
create_task AS (
    SELECT
        id_dag,
        id_run,
        cluster_slot,
        ts_started                                           AS ts_create
    FROM
        lifecycle_task
    WHERE
        operator = 'QuintoAndarEmrCreateClusterOperator'
        AND ts_started IS NOT NULL
),
terminate_task AS (
    SELECT
        id_dag,
        id_run,
        cluster_slot,
        MAX(COALESCE(ts_ended, ts_started))                  AS ts_terminate
    FROM
        lifecycle_task
    WHERE
        operator = 'QuintoAndarEmrTerminateClusterOperator'
        AND COALESCE(ts_ended, ts_started) IS NOT NULL
    GROUP BY
        id_dag,
        id_run,
        cluster_slot
),
-- Two anchors per create: the hour it started in (rank 0) and the next one
-- (rank 1), because a cluster provisioned at 14:59 first bills at 15:00.
-- EXPLODE keeps this an equi-join; a BETWEEN would degrade to a nested-loop
-- range join on EMR.
--
-- The spill anchor is only emitted for creates in the last quarter of an hour.
-- A create at 14:05 whose cluster first bills at 15:00 would mean 55 minutes of
-- provisioning, which EMR does not do; without the cutoff that create would
-- reach into 15:00 and collide with the run that legitimately starts there.
-- Measured: 2,099 of 20,857 creates start at minute >= 45.
create_anchor AS (
    SELECT
        c.id_dag,
        c.id_run,
        c.ts_create,
        t.ts_terminate,
        offset_hours                                         AS anchor_rank,
        TIMESTAMP_SECONDS(
            UNIX_TIMESTAMP(DATE_TRUNC('HOUR', c.ts_create))
            + offset_hours * 3600
        )                                                    AS anchor_hour
    FROM
        create_task AS c
    LEFT JOIN
        terminate_task AS t
            ON  t.id_dag        = c.id_dag
            AND t.id_run        = c.id_run
            AND t.cluster_slot  = c.cluster_slot
    LATERAL VIEW
        EXPLODE(ARRAY(0, 1)) anchors AS offset_hours
    WHERE
        offset_hours = 0
        OR MINUTE(c.ts_create) >= 45
),
candidate AS (
    SELECT
        w.id_emr_cluster,
        a.id_dag,
        a.id_run,
        a.ts_create,
        a.ts_terminate,
        a.anchor_rank
    FROM
        cluster_window AS w
    INNER JOIN
        create_anchor AS a
            ON  a.id_dag      = w.tag_dag_id
            -- Measured: all 2,020,656 EC2 usage rows in 2026-08 start exactly on
            -- the hour. Truncating anyway so a Savings Plan or RI line that ever
            -- carries a finer stamp degrades to a match, not to no_candidate.
            AND a.anchor_hour = DATE_TRUNC('HOUR', w.ts_first_usage)
    WHERE
        w.tag_dag_id IS NOT NULL
),
-- A spill-hour create is a FALLBACK for a cluster with no create in its own
-- first billed hour, never a rival to one. Without this tier filter an hourly
-- DAG self-collides: the create in hour H reaches into H+1 and competes with the
-- run that starts there, so both hours look ambiguous and both go NULL. Measured:
-- 6,831 of 13,815 (dag, create-hour) buckets are preceded by an adjacent hour.
closest_rank AS (
    SELECT
        id_emr_cluster,
        MIN(anchor_rank)                                     AS anchor_rank
    FROM
        candidate
    GROUP BY
        id_emr_cluster
),
candidate_closest AS (
    SELECT
        c.id_emr_cluster,
        c.id_dag,
        c.id_run,
        c.ts_create,
        c.ts_terminate
    FROM
        candidate AS c
    INNER JOIN
        closest_rank AS r
            ON  r.id_emr_cluster = c.id_emr_cluster
            AND r.anchor_rank    = c.anchor_rank
),
matched AS (
    SELECT
        id_emr_cluster,
        MAX(id_dag)                                          AS dag_id,
        MAX(id_run)                                          AS run_id,
        -- Only trust a create/terminate stamp when the cluster has exactly one
        -- candidate; several candidates of one run cannot be told apart, and
        -- MIN/MAX across them would stretch every cluster to the run's window.
        IF(COUNT(*) = 1, MAX(ts_create), NULL)               AS ts_create,
        IF(COUNT(*) = 1, MAX(ts_terminate), NULL)            AS ts_terminate
    FROM
        candidate_closest
    GROUP BY
        id_emr_cluster
    HAVING
        COUNT(DISTINCT id_run) = 1
),
has_candidate AS (
    SELECT DISTINCT
        id_emr_cluster
    FROM
        candidate_closest
),
cluster_event AS (
    SELECT
        id_emr_cluster,
        MAX(cluster_name)                                    AS cluster_name,
        NULLIF(
            REGEXP_EXTRACT(
                MAX(cluster_name),
                '^(.+?)_(?:scheduled|manual|dataset_triggered|backfill|mediator_trig)__',
                1
            ),
            ''
        )                                                    AS dag_id,
        NULLIF(
            REGEXP_EXTRACT(
                MAX(cluster_name),
                '_((?:scheduled|manual|dataset_triggered|backfill|mediator_trig)__.+)$',
                1
            ),
            ''
        )                                                    AS marker_run_id,
        MIN(ts_event)                                        AS ts_started,
        MAX(
            CASE
                WHEN event_state IN ('TERMINATED', 'TERMINATED_WITH_ERRORS')
                    THEN ts_event
            END
        )                                                    AS ts_ended
    FROM
        datalake_emr_events_clean.events
    WHERE
        detail_type = 'EMR Cluster State Change'
        AND id_emr_cluster IS NOT NULL
        AND TO_DATE(CONCAT(year, '-', month, '-', day))
            >= DATE_SUB(DATE('{load_start_date}'), 7)
        AND TO_DATE(CONCAT(year, '-', month, '-', day))
            <  DATE_ADD(DATE('{load_end_date}'), 2)
    GROUP BY
        id_emr_cluster
),
cluster_identity AS (
    SELECT
        w.id_emr_cluster,
        COALESCE(w.tag_dag_id, event.dag_id, m.dag_id)       AS dag_id,
        w.tag_dag_id,
        COALESCE(
            CASE
                WHEN STARTSWITH(event.cluster_name, CONCAT(w.tag_dag_id, '_'))
                    THEN SUBSTRING(event.cluster_name, LENGTH(w.tag_dag_id) + 2)
            END,
            event.marker_run_id,
            m.run_id
        )                                                    AS run_id,
        CASE
            WHEN STARTSWITH(event.cluster_name, CONCAT(w.tag_dag_id, '_'))
                 OR event.marker_run_id IS NOT NULL       THEN 'event'
            WHEN m.run_id IS NOT NULL                     THEN 'resolved'
            WHEN a.id_emr_cluster IS NULL                 THEN 'no_candidate'
            ELSE 'ambiguous'
        END                                                  AS run_match,
        event.cluster_name,
        COALESCE(event.ts_started, m.ts_create, w.ts_first_usage)
                                                             AS ts_cluster_started,
        COALESCE(event.ts_ended, m.ts_terminate, w.ts_last_usage)
                                                             AS ts_cluster_ended,
        w.tag_provisioner,
        w.tag_owner,
        w.tag_environment,
        w.tag_cost_center,
        w.tag_ecosystem,
        w.tag_data_classification,
        w.tag_sensitive_data
    FROM
        cluster_window AS w
    LEFT JOIN
        cluster_event AS event
            ON event.id_emr_cluster = w.id_emr_cluster
    LEFT JOIN
        matched AS m
            ON m.id_emr_cluster = w.id_emr_cluster
    LEFT JOIN
        has_candidate AS a
            ON a.id_emr_cluster = w.id_emr_cluster
)
SELECT
    e.id_emr_cluster,
    e.id_ec2_instance,
    i.dag_id,
    i.tag_dag_id,
    i.run_id,
    i.run_match,
    COALESCE(
        i.cluster_name,
        CASE
            WHEN i.dag_id IS NOT NULL AND i.run_id IS NOT NULL
                THEN CONCAT(i.dag_id, '_', i.run_id)
            ELSE i.dag_id
        END
    )                                                        AS cluster_name,
    e.instance_role,
    e.market,
    e.instance_type,
    v.ebs_volume_ids,
    e.instance_hours_in_day,
    i.ts_cluster_started                                     AS ts_instance_started,
    i.ts_cluster_ended                                       AS ts_instance_ended,
    i.ts_cluster_started,
    i.ts_cluster_ended,
    COALESCE(i.tag_provisioner, e.tag_provisioner, 'emr')    AS tag_provisioner,
    COALESCE(i.tag_owner, e.tag_owner)                       AS tag_owner,
    COALESCE(i.tag_environment, e.tag_environment)           AS tag_environment,
    COALESCE(i.tag_cost_center, e.tag_cost_center)           AS tag_cost_center,
    COALESCE(i.tag_ecosystem, e.tag_ecosystem)               AS tag_ecosystem,
    COALESCE(i.tag_data_classification, e.tag_data_classification)
                                                             AS tag_data_classification,
    COALESCE(i.tag_sensitive_data, e.tag_sensitive_data)     AS tag_sensitive_data,
    CURRENT_TIMESTAMP()                                      AS ts_load,
    e.dt_cluster_run
FROM
    ec2 AS e
INNER JOIN
    cluster_identity AS i
        ON i.id_emr_cluster = e.id_emr_cluster
LEFT JOIN
    ebs_by_cluster_day AS v
        ON  v.id_emr_cluster = e.id_emr_cluster
        AND v.dt_cluster_run = e.dt_cluster_run
