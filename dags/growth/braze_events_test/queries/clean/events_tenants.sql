SELECT DISTINCT
    id,
    event_info,
    event_type,
    year,
    month,
    day
FROM
    datalake_braze_events_test_raw.events_tenants
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}