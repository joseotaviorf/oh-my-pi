SELECT
    id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    LOWER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = 170698
    AND event_type = 'visit_schedule_continue_clicked'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
