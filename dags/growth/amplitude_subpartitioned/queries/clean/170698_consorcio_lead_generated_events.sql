SELECT
    id_amplitude,
    id_user,
    id_device,
    id_event,
    id_app,
    id_session,
    event_type,
    city,
    country,
    NULLIF(GET_JSON_OBJECT(event_properties, '$.customer_journey'),'') as ep_costumer_journey,
    NULLIF(GET_JSON_OBJECT(event_properties, '$.referrer'),'') as ep_referrer,
    NULLIF(GET_JSON_OBJECT(event_properties, '$.formfield_lead_id'),'') as ep_consorcio_uuid,
    NULLIF(GET_JSON_OBJECT(event_properties, '$.content_type'),'') as ep_content_type,
    NULLIF(GET_JSON_OBJECT(event_properties, '$.platform'),'') as ep_platform,
    NULLIF(PARSE_URL(GET_JSON_OBJECT(event_properties, '$.uri'),'QUERY', 'utm_source'),'') as ep_utm_source,
    NULLIF(PARSE_URL(GET_JSON_OBJECT(event_properties, '$.uri'),'QUERY', 'utm_medium'),'') as ep_utm_medium,
    NULLIF(PARSE_URL(GET_JSON_OBJECT(event_properties, '$.uri'),'QUERY', 'utm_campaign'),'') as ep_utm_campaign,
    NULLIF(GET_JSON_OBJECT(user_properties, '$.utm_source'),'') as up_utm_source,
    NULLIF(GET_JSON_OBJECT(user_properties, '$.utm_medium'),'') as up_utm_medium,
    NULLIF(GET_JSON_OBJECT(user_properties, '$.utm_campaign'),'') as up_utm_campaign,
    NULLIF(GET_JSON_OBJECT(user_properties, '$.ab_beakman_consorcio_new_landing_page'), '') as up_ab_beakman_consorcio_new_landing_page,
    event_properties,
    user_properties,
    ts_event,
    ts_server_uploaded,
    ts_client_event,
    ts_client_uploaded,
    ts_processed,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '170698' AND event_type = 'consorcio.lead_generated'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
