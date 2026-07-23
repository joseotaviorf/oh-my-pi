SELECT
    id_amplitude,
    id_event,
    id_user,
    GET_JSON_OBJECT(event_properties, '$.house_id') AS id_house,
    GET_JSON_OBJECT(event_properties, '$.sk_offer') AS id_offer,
    GET_JSON_OBJECT(event_properties, '$.offers_status') AS offer_status,
    country,
    region,
    city,
    device_type,
    os_name,
    GET_JSON_OBJECT(event_properties, '$.platform_type') AS platform,
    uuid,
    GET_JSON_OBJECT(user_properties, '$.login_status') AS login_status,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 440441
    AND event_type = 'sale_offer_list_details_button_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
