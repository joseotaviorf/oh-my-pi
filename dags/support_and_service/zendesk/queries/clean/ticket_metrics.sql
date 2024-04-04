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
    CAST(requester_updated_at AS TIMESTAMP) AS ts_requester_updated,
    CAST(solved_at AS TIMESTAMP) AS ts_solved,
    CAST(latest_comment_added_at AS TIMESTAMP) AS ts_latest_comment_added,
    CAST(assigned_at AS TIMESTAMP) AS ts_assigned,
    CAST(initially_assigned_at AS TIMESTAMP) AS ts_initially_assigned,
    CAST(assignee_updated_at AS TIMESTAMP) AS ts_assignee_updated,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_zendesk_raw.ticket_metrics
WHERE
    dt IN (MAKE_DATE({year}, {month}, {day}), MAKE_DATE({year}, {month}, {day}) + INTERVAL 1 DAY)
    AND updated_at >= TIMESTAMP(MAKE_DATE({year}, {month}, {day})) + INTERVAL 3 HOUR
    AND updated_at < TIMESTAMP(MAKE_DATE({year}, {month}, {day}) + INTERVAL 1 DAY) + INTERVAL 3 HOUR
QUALIFY
    ROW_NUMBER() OVER(PARTITION BY id_ticket_metric, ts_updated ORDER BY dt_extracted DESC) = 1
)
SELECT
    id_ticket_metric,
    id_ticket,
    assignee_stations,
    reopens,
    replies,
    group_stations,
    url,
    STR_TO_MAP(REGEXP_REPLACE(reply_time_in_minutes, ',$|\\{{|\\}}|"', "")) AS reply_time_min,
    STR_TO_MAP(REGEXP_REPLACE(first_resolution_time_in_minutes, ',$|\\{{|\\}}|"', "")) AS first_resolution_time_min,
    STR_TO_MAP(REGEXP_REPLACE(full_resolution_time_in_minutes, ',$|\\{{|\\}}|"', "")) AS full_resolution_time_min,
    STR_TO_MAP(REGEXP_REPLACE(requester_wait_time_in_minutes, ',$|\\{{|\\}}|"', "")) AS requester_wait_time_min,
    STR_TO_MAP(REGEXP_REPLACE(agent_wait_time_in_minutes, ',$|\\{{|\\}}|"', "")) AS agent_wait_time_min,
    STR_TO_MAP(REGEXP_REPLACE(on_hold_time_in_minutes, ',$|\\{{|\\}}|"', "")) AS on_hold_time_min,
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
