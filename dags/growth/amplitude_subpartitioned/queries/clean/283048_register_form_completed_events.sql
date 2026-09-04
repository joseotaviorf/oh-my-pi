SELECT
    id_amplitude,
    id_event,
    id_device,
    country AS user_country,
	GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
    GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
    user_properties,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = 283048
    AND event_type = 'register_form_completed'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
