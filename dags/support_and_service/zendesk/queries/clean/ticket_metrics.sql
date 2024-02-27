SELECT
    id AS id_ticket_metric,
    ticket_id AS id_ticket,
    assignee_stations,
    reopens,
    replies,
    group_stations,
    url,
    reply_time_in_minutes,
    first_resolution_time_in_minutes,
    full_resolution_time_in_minutes,
    requester_wait_time_in_minutes,
    agent_wait_time_in_minutes,
    on_hold_time_in_minutes,
    dt AS dt_extracted,
    requester_updated_at AS ts_requester_updated,
    solved_at AS ts_solved,
    latest_comment_added_at AS ts_latest_comment_added,
    assigned_at AS ts_assigned,
    initially_assigned_at AS ts_initially_assigned,
    assignee_updated_at AS ts_assignee_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load,
    YEAR(dt) AS year,
    MONTH(dt) AS month,
    DAY(dt) AS day
FROM
    datalake_zendesk_tickets_raw.ticket_metrics
WHERE
    dt IN (CAST('{year}-{month}-{day}' AS DATE), CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY)
