SELECT
    id_user,
    get_json_object(event_properties, '$.house_id') AS id_house,
    get_json_object(event_properties, '$.business_context') AS business_context,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '170698' AND event_type = 'visit_schedule_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
