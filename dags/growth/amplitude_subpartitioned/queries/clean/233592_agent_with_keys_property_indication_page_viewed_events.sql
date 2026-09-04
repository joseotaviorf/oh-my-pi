SELECT
    id_user,
    GET_JSON_OBJECT(event_properties, '$.origin') AS origin,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = 233592
    AND event_type = 'agent_with_keys_property_indication_page_viewed'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
