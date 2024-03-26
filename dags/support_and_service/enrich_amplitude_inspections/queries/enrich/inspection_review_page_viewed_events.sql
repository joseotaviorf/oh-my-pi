SELECT DISTINCT 
    id_app,
    id_amplitude,
    id_event,
    id_user,
    get_json_object(event_properties, '$.inspection_id') AS id_client_side,
    get_json_object(event_properties, '$.contract_id') AS id_contract,
    get_json_object(event_properties, '$.inspection_type') AS inspection_type,
    get_json_object(event_properties, '$.user_type') AS user_type,
    get_json_object(event_properties, '$.uri') AS uri,
    event_properties,
    user_properties,
    event_type,
    ts_user_created,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170698_inspection_review_home_page_viewed_events
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}

UNION ALL

SELECT DISTINCT 
    id_app,
    id_amplitude,
    id_event,
    id_user,
    get_json_object(event_properties, '$.inspection_id') AS id_client_side,
    get_json_object(event_properties, '$.contract_id') AS id_contract,
    get_json_object(event_properties, '$.inspection_type') AS inspection_type,
    get_json_object(event_properties, '$.user_type') AS user_type,
    get_json_object(event_properties, '$.uri') AS uri,
    event_properties,
    user_properties,
    event_type,
    ts_user_created,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.170135_inspection_review_home_page_viewed_events
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}