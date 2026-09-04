SELECT
    id_user,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = 233592
    AND event_type = 'home_page_viewed'
    AND year = {year} AND month = {month} AND day = {day}
