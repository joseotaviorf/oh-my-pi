SELECT
    id,
    event_id AS id_event,
    subscription_id AS id_subscription,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_reports_raw.processed_event
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}