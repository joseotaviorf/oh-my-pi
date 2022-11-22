SELECT
    id,
    title,
    folder_id,
    description,
    last_accessed_at,
    user_id,
    url,
    created_at,
    updated_at,
    year,
    month,
    day
FROM
    datalake_looker_raw.dashboards
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
