SELECT 
    id,
    user_id AS id_user,
    dashboard_id AS id_dashboard,
    slice_id AS id_slice,
    action,
    json,
    duration_ms,
    referrer,
    dttm AS ts_event,
    year,
    month,
    day
FROM datalake_superset_raw.logs
WHERE year = {year} AND month = {month} AND day = {day}