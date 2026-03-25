SELECT
    id_amplitude,
    id_app,
    id_event,
    id_session,
    id_inserted,
    id_user,
    city,
    country,
    event_type,
    GET_JSON_OBJECT(event_properties, '$.module') AS homepage_module,
    GET_JSON_OBJECT(event_properties, '$.section') AS homepage_section,
    GET_JSON_OBJECT(event_properties, '$.subSection') AS homepage_sub_section,
    GET_JSON_OBJECT(event_properties, '$.value') AS click_value,
    ts_event,
    DATE(ts_event) AS dt_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '417002' AND event_type = 'HomePageClick'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
