SELECT
    CAST(GET_JSON_OBJECT(event_properties, '$.property_id') AS BIGINT) AS id_house,
    CAST(id_user AS BIGINT) AS id_user,
    UPPER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    event_properties,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    event_type = 'property_publish_success'
    AND id_app = 370096
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )
