WITH tasks_updated AS (
    WITH t_max AS (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY year DESC, month DESC, day DESC, ts_start DESC) AS rn
        FROM
            datalake_crm.tasks
        WHERE
            type IN ('ConverterLead', 'ConverterLeadPrioritario')
    )
    SELECT *
    FROM t_max
    WHERE rn = 1
),
task_reference_inbound_event_histories AS (
  WITH task_reference_inbound_event_histories_last_update AS (
    SELECT
        id_task,
        MAX(ts_updated) AS max_ts_updated
    FROM datalake_autodialer_clean.task_reference_inbound_event_histories
    GROUP BY 1
  )
  SELECT
    t.id_task,
    t.event_date,
    t.task_reference_event_origin
  FROM
    datalake_autodialer_clean.task_reference_inbound_event_histories t
  JOIN
    task_reference_inbound_event_histories_last_update trlu
    ON trlu.id_task = t.id_task
    AND trlu.max_ts_updated = t.ts_updated
),
first_call AS (
    SELECT
        id_task,
        MIN(CASE WHEN task_reference_event_origin = 'WEB_HOOK_BEFORE_NOTIFICATION' THEN event_date END) AS ts_first_call,
        MIN(CASE WHEN task_reference_event_origin = 'WEB_HOOK_AFTER_NOTIFICATION' THEN event_date END) AS ts_first_connection
    FROM task_reference_inbound_event_histories
    WHERE task_reference_event_origin IN ('WEB_HOOK_BEFORE_NOTIFICATION','WEB_HOOK_AFTER_NOTIFICATION')
    GROUP BY 1
),
task_references AS (
  WITH task_references_last_update AS (
    SELECT
        id_task,
        MAX(ts_updated) AS max_ts_updated
    FROM datalake_autodialer_clean.task_references
    GROUP BY 1
  )
  SELECT
      r.id_task,
      r.is_active,
      r.ts_created
  FROM
    datalake_autodialer_clean.task_references r
  JOIN
    task_references_last_update trlu
    ON trlu.id_task = r.id_task
    AND trlu.max_ts_updated = r.ts_updated
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
    CAST(l.id AS INTEGER) AS sk_lead,
    t.id AS sk_task,
    CAST(DATE_FORMAT(r.ts_created, 'yyyyMMdd') AS INTEGER) AS sk_imported_to_task_references_date,
    r.ts_created AS ts_imported_to_task_references,
    CAST(r.is_active AS BOOLEAN) AS is_active_in_task_references,
    CAST(NULL AS INTEGER) AS sk_imported_to_mailing_list_date, -- Deprecated column from datalake_raw.autodialer_mailing_list
    CAST(NULL AS TIMESTAMP) AS ts_imported_to_mailing_list, -- Deprecated column from datalake_raw.autodialer_mailing_list
    CAST(NULL AS BOOLEAN) AS is_active_in_mailing_list, -- Deprecated column from datalake_raw.autodialer_mailing_list
    CAST(DATE_FORMAT(events.ts_first_call, 'yyyyMMdd') AS INTEGER) AS sk_first_call_date,
    events.ts_first_call,
    CAST(DATE_FORMAT(events.ts_first_connection, 'yyyyMMdd') AS INTEGER) AS sk_first_connection_date,
    events.ts_first_connection,
    FALSE AS is_mailing_active, -- Deprecated column from datalake_raw.autodialer_mailing_list
    FALSE AS is_mailing_paused, -- Deprecated column from datalake_raw.autodialer_mailing_list
    NOW() AS ts_load
FROM
    datalake_ebdb_clean.lead l
JOIN
    tasks_updated t
    ON t.id_origin = CAST(l.id AS VARCHAR(24))
LEFT JOIN
    task_references r
    ON r.id_task = t.id
LEFT JOIN
    first_call events
    ON events.id_task = t.id
WHERE COALESCE(l.has_processed, TRUE)