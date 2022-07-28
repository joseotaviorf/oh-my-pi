SELECT DISTINCT
    id,
    event_info,
    event_type,
    year,
    month,
    day
FROM
    datalake_braze_events_raw.events_indica_ai
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}