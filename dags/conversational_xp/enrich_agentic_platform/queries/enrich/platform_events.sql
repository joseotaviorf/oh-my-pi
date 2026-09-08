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
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
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
