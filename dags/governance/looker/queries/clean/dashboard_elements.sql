SELECT
    id,
    title,
    type,
    dashboard_id,
    look_id,
    query_id,
    year,
    month,
    day
FROM
    datalake_looker_raw.dashboard_elements
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
