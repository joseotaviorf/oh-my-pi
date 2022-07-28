SELECT
    canvas_id AS id_canvas,
    `name` AS canvas_name,
    stats,
    year,
    month,
    day
FROM
    datalake_braze_analytics_raw.canvas_analytics_tenants
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}