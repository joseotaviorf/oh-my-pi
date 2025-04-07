SELECT
    id_amplitude,
    id_event,
    id_user,
    GET_JSON_OBJECT(user_properties, '$.company_id') AS company_id,
    GET_JSON_OBJECT(user_properties, '$.email') AS email,
    GET_JSON_OBJECT(user_properties, '$.login_status') AS login_status,
    GET_JSON_OBJECT(user_properties, '$.source') AS source,
    GET_JSON_OBJECT(user_properties, '$.product') AS product,
    GET_JSON_OBJECT(user_properties, '$.role') AS role,
    language,
    city,
    id_device,
    device_type,
    os_name,
    platform,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_new_clean.events
WHERE
    id_app = '440441' AND event_type = 'home_page_viewed'
