SELECT 
    id_amplitude,
    BIGINT(id_user) AS id_user, 
    id_device, 
    BIGINT(GET_JSON_OBJECT(event_properties, '$.house_id')) AS id_house,
    BIGINT(GET_JSON_OBJECT(event_properties, '$.contract_id')) AS id_contract,
    INT(GET_JSON_OBJECT(event_properties, '$.test_group')) AS id_test_group,
    event_type,
    event_properties,
    ts_event,
    ts_processed,
    year,
    month,
    day
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = '183047' AND event_type = 'house_in_early_relisting'
    AND (
        (year > YEAR('{load_start_date}') OR (year = YEAR('{load_start_date}') AND (month > MONTH('{load_start_date}') OR (month = MONTH('{load_start_date}') AND day >= DAY('{load_start_date}')))))
        AND (year < YEAR('{load_end_date}') OR (year = YEAR('{load_end_date}') AND (month < MONTH('{load_end_date}') OR (month = MONTH('{load_end_date}') AND day <= DAY('{load_end_date}')))))
    )