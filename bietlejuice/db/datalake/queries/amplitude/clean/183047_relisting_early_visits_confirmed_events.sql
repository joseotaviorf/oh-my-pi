SELECT 
    id_amplitude,
    BIGINT(id_user) AS id_user, 
    id_device, 
    BIGINT(GET_JSON_OBJECT(event_properties, '$.house_id')) AS id_house,
    GET_JSON_OBJECT(user_properties, '$.country') AS country_code,
    event_type,
    user_properties,
    event_properties,
    ts_event,
    ts_processed,
    year,
    month,
    day
FROM
    datalake_amplitude_clean_staging.183047_relisting_early_visits_confirmed_events
WHERE
    year={} 
    AND month={} 
    AND day={}