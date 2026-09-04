SELECT
    id_amplitude,
    id_app,
    BIGINT(id_user) AS id_user,
    GET_JSON_OBJECT(event_properties, '$.intent') AS intent,
    INT(GET_JSON_OBJECT(event_properties, '$.experiment_attribution_v1')) AS experiment_attribution_v1,
    GET_JSON_OBJECT(event_properties, '$.privacy') AS privacy,
    event_type,
    event_properties,
    TO_TIMESTAMP(GET_JSON_OBJECT(event_properties, '$.date')) AS ts_event_properties,
    ts_event,
    ts_processed,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = '170698' AND event_type = 'concierge_trigger'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
