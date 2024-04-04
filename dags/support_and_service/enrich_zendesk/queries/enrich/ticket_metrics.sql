SELECT DISTINCT
    id_ticket,
    group_stations,
    assignee_stations,
    reopens,
    replies,
    reply_time_min["calendar"] AS reply_time_min_calendar,
    first_resolution_time_min["calendar"] AS first_resolution_time_min_calendar,
    full_resolution_time_min["calendar"] AS full_resolution_time_min_calendar,
    requester_wait_time_min["calendar"] AS requester_wait_time_min_calendar,
    agent_wait_time_min["calendar"] AS agent_wait_time_min_calendar,
    on_hold_time_min["calendar"] AS on_hold_time_min_calendar,
    reply_time_min["business"] AS reply_time_min_business,
    first_resolution_time_min["business"] AS first_resolution_time_min_business,
    full_resolution_time_min["business"] AS full_resolution_time_min_business,
    requester_wait_time_min["business"] AS requester_wait_time_min_business,
    agent_wait_time_min["business"] AS agent_wait_time_min_business,
    on_hold_time_min["business"] AS on_hold_time_min_business,
    ts_assigned,
    ts_initially_assigned,
    ts_solved,
    ts_latest_comment_added,
    ts_created,
    ts_updated,
    NOW() AS ts_load,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_zendesk_clean.ticket_metrics
WHERE
    year IN (YEAR(CAST('{year}-{month}-{day}' AS DATE)), YEAR(CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY))
    AND month IN (MONTH(CAST('{year}-{month}-{day}' AS DATE)), MONTH(CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY))
    AND day IN (DAY(CAST('{year}-{month}-{day}' AS DATE)), DAY(CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY))
    AND ts_updated <= TIMESTAMP(CAST("{year}-{month}-{day}" AS DATE) + INTERVAL 1 DAY) + INTERVAL 3 HOUR
