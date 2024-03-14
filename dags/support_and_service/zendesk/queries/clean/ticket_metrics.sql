WITH ticket_metrics AS (
  SELECT DISTINCT
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
    CAST(dt AS DATE) AS dt_extracted,
    requester_updated_at AS ts_requester_updated,
    solved_at AS ts_solved,
    latest_comment_added_at AS ts_latest_comment_added,
    assigned_at AS ts_assigned,
    initially_assigned_at AS ts_initially_assigned,
    assignee_updated_at AS ts_assignee_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    YEAR(dt) AS year,
    MONTH(dt) AS month,
    DAY(dt) AS day
FROM
    datalake_zendesk_raw.ticket_metrics
WHERE
    dt IN (CAST('{year}-{month}-{day}' AS DATE), CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY)
)
SELECT
    id_ticket_metric,
    id_ticket,
    assignee_stations,
    reopens,
    replies,
    group_stations,
    url,
    STR_TO_MAP(REGEXP_REPLACE(reply_time_in_minutes, ',\\$|\\{|\\}|"', "")) AS reply_time_min,
    STR_TO_MAP(REGEXP_REPLACE(first_resolution_time_in_minutes, ',\\$|\\{|\\}|"', "")) AS first_resolution_time_min,
    STR_TO_MAP(REGEXP_REPLACE(full_resolution_time_in_minutes, ',\\$|\\{|\\}|"', "")) AS full_resolution_time_min,
    STR_TO_MAP(REGEXP_REPLACE(requester_wait_time_in_minutes, ',\\$|\\{|\\}|"', "")) AS requester_wait_time_min,
    STR_TO_MAP(REGEXP_REPLACE(agent_wait_time_in_minutes, ',\\$|\\{|\\}|"', "")) AS agent_wait_time_min,
    STR_TO_MAP(REGEXP_REPLACE(on_hold_time_in_minutes, ',\\$|\\{|\\}|"', "")) AS on_hold_time_min,
    dt_extracted,
    ts_requester_updated,
    ts_solved,
    ts_latest_comment_added,
    ts_assigned,
    ts_initially_assigned,
    ts_assignee_updated,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    ticket_metrics
