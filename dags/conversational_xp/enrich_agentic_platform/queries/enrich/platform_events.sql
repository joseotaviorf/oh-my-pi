-- Processes a single hour of a single date partition: {load_start_date} and
-- {load_end_date} must be 'YYYY-MM-DD HH:00:00' timestamps one hour apart.
-- A date-only value (e.g. from the Airflow trigger form) selects no rows.
WITH ranked_events AS (
    SELECT
        id_event,
        id_person,
        id_user,
        event_name,
        event_properties,
        ts_event,
        ROW_NUMBER() OVER (
            PARTITION BY id_event
            ORDER BY ts_load DESC, ts_egw DESC
        ) AS event_rank
    FROM
        datalake_cdp_clean.user_tracking
    WHERE
        year = YEAR('{load_start_date}')
        AND month = MONTH('{load_start_date}')
        AND day = DAY('{load_start_date}')
        AND ts_event >= TIMESTAMP('{load_start_date}')
        AND ts_event < TIMESTAMP('{load_end_date}')
        AND (
            event_name RLIKE '^agentic_platform_'
            OR event_name = 'agentic_tool_call_completed'
        )
)

SELECT
    id_event,
    id_person,
    id_user,
    event_name,
    event_properties,
    ts_event
FROM
    ranked_events
WHERE
    event_rank = 1
