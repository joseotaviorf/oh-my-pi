-- Own-instrumentation health: turns where the agent skipped or failed a required
-- trajectory event. Not a user-facing usage metric — this is a data-quality signal
-- for the Tars/unstable-srat skill authors on their own telemetry pipeline.
WITH protocol_gaps AS (
    SELECT
        id_session,
        session_source,
        'protocol_gap' AS issue_source,
        event_type,
        NULL AS outcome,
        blocking_step,
        detail,
        last_assistant_message_preview,
        ts_event,
        dt_event,
        year,
        month,
        day
    FROM
        datalake_tars_clean.vector_logs
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND event_type = 'protocol_gap'
),
turn_issues AS (
    SELECT
        id_session,
        session_source,
        'turn_end' AS issue_source,
        event_type,
        outcome,
        NULL AS blocking_step,
        NULL AS detail,
        NULL AS last_assistant_message_preview,
        ts_event,
        dt_event,
        year,
        month,
        day
    FROM
        datalake_tars_clean.vector_logs
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
        AND event_type = 'turn_end'
        AND outcome IN ('gap', 'hook_error', 'no_tars_activity')
)
SELECT
    CONCAT(issue_source, '-', id_session, '-', CAST(UNIX_TIMESTAMP(ts_event) AS STRING)) AS id_issue,
    id_session,
    session_source,
    issue_source,
    event_type,
    outcome,
    blocking_step,
    detail,
    last_assistant_message_preview,
    ts_event AS ts_issue,
    dt_event AS dt_issue,
    year,
    month,
    day
FROM
    protocol_gaps
UNION ALL
SELECT
    CONCAT(issue_source, '-', id_session, '-', CAST(UNIX_TIMESTAMP(ts_event) AS STRING)) AS id_issue,
    id_session,
    session_source,
    issue_source,
    event_type,
    outcome,
    blocking_step,
    detail,
    last_assistant_message_preview,
    ts_event AS ts_issue,
    dt_event AS dt_issue,
    year,
    month,
    day
FROM
    turn_issues
