SELECT DISTINCT
    id_ticket,
    group_stations,
    assignee_stations,
    reopens,
    replies,
    CAST(reply_time_min["calendar"] AS INT) AS reply_time_min_calendar,
    CAST(first_resolution_time_min["calendar"] AS INT) AS first_resolution_time_min_calendar,
    CAST(full_resolution_time_min["calendar"] AS INT) AS full_resolution_time_min_calendar,
    CAST(requester_wait_time_min["calendar"] AS INT) AS requester_wait_time_min_calendar,
    CAST(agent_wait_time_min["calendar"] AS INT) AS agent_wait_time_min_calendar,
    CAST(on_hold_time_min["calendar"] AS INT) AS on_hold_time_min_calendar,
    CAST(reply_time_min["business"] AS INT) AS reply_time_min_business,
    CAST(first_resolution_time_min["business"] AS INT) AS first_resolution_time_min_business,
    CAST(full_resolution_time_min["business"] AS INT) AS full_resolution_time_min_business,
    CAST(requester_wait_time_min["business"] AS INT) AS requester_wait_time_min_business,
    CAST(agent_wait_time_min["business"] AS INT) AS agent_wait_time_min_business,
    CAST(on_hold_time_min["business"] AS INT) AS on_hold_time_min_business,
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
