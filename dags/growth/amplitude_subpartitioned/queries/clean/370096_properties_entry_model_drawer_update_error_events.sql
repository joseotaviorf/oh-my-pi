SELECT
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS id_house,
    CAST(GET_JSON_OBJECT(event_properties, '$.user_id') AS BIGINT) AS id_user,
    GET_JSON_OBJECT(event_properties, '$.step_name') AS step_name,
    GET_JSON_OBJECT(event_properties, '$.error_type') AS error_type,
    GET_JSON_OBJECT(event_properties, '$.selected_entry_access') AS selected_entry_access,
    city,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    event_type = 'properties_entry_model_drawer_update_error'
    AND id_app = 370096
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
