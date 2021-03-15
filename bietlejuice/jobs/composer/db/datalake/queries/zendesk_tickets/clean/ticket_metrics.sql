WITH stitch_data AS (
    SELECT
        tm.*,
        ROW_NUMBER() OVER (PARTITION BY tm.id, tm.dt ORDER BY tm.updated_at DESC) AS last_updated
    FROM
        datalake_zendesk_tickets_raw.ticket_metrics tm
    WHERE
        tm.dt = '{year}-{month}-{day}'
)
SELECT
    id AS id_ticket_metrics,
    url AS url_ticket_metrics,
    assignee_stations,
    reopens,
    ticket_id AS id_ticket,
    replies,
    group_stations,
    CAST(NULLIF(GET_JSON_OBJECT(reply_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_reply_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(reply_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_reply_business,
    CAST(NULLIF(GET_JSON_OBJECT(first_resolution_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_first_resolution_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(first_resolution_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_first_resolution_business,
    CAST(NULLIF(GET_JSON_OBJECT(full_resolution_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_full_resolution_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(full_resolution_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_full_resolution_business,
    CAST(NULLIF(GET_JSON_OBJECT(requester_wait_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_requester_wait_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(requester_wait_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_requester_wait_business,
    CAST(NULLIF(GET_JSON_OBJECT(agent_wait_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_agent_wait_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(agent_wait_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_agent_wait_business,
    CAST(NULLIF(GET_JSON_OBJECT(on_hold_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_on_hold_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(on_hold_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_on_hold_business,
    dt AS dt_extracted,
    CAST(requester_updated_at AS TIMESTAMP) AS ts_requester_updated,
    CAST(solved_at AS TIMESTAMP) AS ts_solved,
    CAST(latest_comment_added_at AS TIMESTAMP) AS ts_latest_comment_added,
    CAST(initially_assigned_at AS TIMESTAMP) AS ts_initially_assigned,
    CAST(assignee_updated_at AS TIMESTAMP) AS ts_assignee_updated,
    CAST(assigned_at AS TIMESTAMP) AS ts_assigned,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(dt AS DATE)) AS year,
    MONTH(CAST(dt AS DATE)) AS month,
    DAY(CAST(dt AS DATE)) AS day
FROM
    stitch_data
WHERE
    last_updated = 1
