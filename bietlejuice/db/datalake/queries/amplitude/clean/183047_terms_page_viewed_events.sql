SELECT
    id_amplitude, 
    id_user, 
    id_device, 
    event_type, 
    STRING(GET_JSON_OBJECT(user_properties, '$.ab_rental_owner_adm')) AS ab_rental_owner_adm,
    STRING(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    user_properties, 
    event_properties,
    ts_event,
    ts_processed,
    year,
    month,
    day
FROM
    datalake_amplitude_clean_staging.183047_terms_page_viewed_events
WHERE
    year={} 
    AND month={} 
    AND day={}