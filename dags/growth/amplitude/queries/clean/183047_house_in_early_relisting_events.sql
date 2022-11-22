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
    datalake_amplitude_clean_staging.183047_house_in_early_relisting_events
WHERE
    year={} 
    AND month={} 
    AND day={}