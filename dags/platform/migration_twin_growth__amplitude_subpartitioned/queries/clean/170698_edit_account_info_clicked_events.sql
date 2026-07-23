-- QuintoAndar Classifieds (QAC): edit_account_info_clicked event (app 170698)
SELECT
    id_amplitude,
    id_app,
    id_device,
    id_event,
    id_session,
    id_user,
    CAST(GET_JSON_OBJECT(event_properties, '$.sub_region_id') AS INTEGER) AS id_region,
    CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS INTEGER) AS id_house,
    CAST(GET_JSON_OBJECT(event_properties, '$.search_id') AS STRING) AS id_search,
    CAST(GET_JSON_OBJECT(event_properties, '$.lead_id') AS STRING) AS id_lead,
    CAST(GET_JSON_OBJECT(event_properties, '$.source_id') AS STRING) AS id_source,
    CAST(GET_JSON_OBJECT(event_properties, '$.publisher_id') AS STRING) AS id_publisher,
    CAST(GET_JSON_OBJECT(event_properties, '$.search_rank') AS STRING) AS search_rank,
    CAST(GET_JSON_OBJECT(event_properties, '$.publisher_name') AS STRING) AS publisher_name,
    CAST(GET_JSON_OBJECT(event_properties, '$.city') AS STRING) AS city,
    CAST(GET_JSON_OBJECT(event_properties, '$.origin') AS STRING) AS origin,
    CAST(GET_JSON_OBJECT(event_properties, '$.uri') AS STRING) AS uri,
    COALESCE(LOWER(CAST(GET_JSON_OBJECT(event_properties, '$.business_context') AS STRING)), 'rent') AS business_context,
    TRUE AS is_qac,
    event_type,
    platform,
    event_properties,
    user_properties,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '170698'
    AND event_type = 'edit_account_info_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
