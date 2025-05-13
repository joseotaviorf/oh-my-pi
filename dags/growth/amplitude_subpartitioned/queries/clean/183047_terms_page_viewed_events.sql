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
    datalake_amplitude_new_clean.events
WHERE
    id_app = '183047' AND event_type = 'terms_page_viewed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'