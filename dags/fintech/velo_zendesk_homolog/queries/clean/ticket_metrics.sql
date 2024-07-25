WITH max_stitch_data AS (
    SELECT
        id,
        MAX(CAST(updated_at AS TIMESTAMP)) AS max_updated_at
    FROM
        datalake_velo_zendesk_homolog_raw.ticket_metrics
    GROUP BY 1
)
SELECT
    tm.id AS id_ticket_metrics,
    tm.url AS url_ticket_metrics,
    tm.assignee_stations,
    tm.reopens,
    tm.ticket_id AS id_ticket,
    tm.replies,
    tm.group_stations,
    CAST(NULLIF(GET_JSON_OBJECT(tm.reply_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_reply_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(tm.reply_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_reply_business,
    CAST(NULLIF(GET_JSON_OBJECT(tm.first_resolution_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_first_resolution_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(tm.first_resolution_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_first_resolution_business,
    CAST(NULLIF(GET_JSON_OBJECT(tm.full_resolution_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_full_resolution_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(tm.full_resolution_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_full_resolution_business,
    CAST(NULLIF(GET_JSON_OBJECT(tm.requester_wait_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_requester_wait_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(tm.requester_wait_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_requester_wait_business,
    CAST(NULLIF(GET_JSON_OBJECT(tm.agent_wait_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_agent_wait_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(tm.agent_wait_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_agent_wait_business,
    CAST(NULLIF(GET_JSON_OBJECT(tm.on_hold_time_in_minutes,'$.calendar'), 'null') AS INTEGER) AS minutes_on_hold_calendar,
    CAST(NULLIF(GET_JSON_OBJECT(tm.on_hold_time_in_minutes,'$.business'), 'null') AS INTEGER) AS minutes_on_hold_business,
    tm.dt AS dt_extracted,
    CAST(tm.requester_updated_at AS TIMESTAMP) AS ts_requester_updated,
    CAST(tm.solved_at AS TIMESTAMP) AS ts_solved,
    CAST(tm.latest_comment_added_at AS TIMESTAMP) AS ts_latest_comment_added,
    CAST(tm.initially_assigned_at AS TIMESTAMP) AS ts_initially_assigned,
    CAST(tm.assignee_updated_at AS TIMESTAMP) AS ts_assignee_updated,
    CAST(tm.assigned_at AS TIMESTAMP) AS ts_assigned,
    CAST(tm.created_at AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(tm.created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(tm.updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(tm.updated_at AS DATE)) AS year,
    MONTH(CAST(tm.updated_at AS DATE)) AS month,
    DAY(CAST(tm.updated_at AS DATE)) AS day
FROM
    datalake_velo_zendesk_homolog_raw.ticket_metrics tm
JOIN
    max_stitch_data max_sd
        ON max_sd.id = tm.id
        AND max_sd.max_updated_at = CAST(tm.updated_at AS TIMESTAMP)
