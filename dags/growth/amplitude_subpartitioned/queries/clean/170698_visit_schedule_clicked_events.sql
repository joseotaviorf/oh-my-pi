SELECT
    uuid AS uuid_event,
    id_user,
    GET_JSON_OBJECT(event_properties, '$.house_id') AS id_house,
    LOWER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    FROM_JSON(GET_JSON_OBJECT(event_properties,'$.agent_assignment_type_options'), 'array<string>') AS agent_assignment_type_options,
    GET_JSON_OBJECT(event_properties,'$.agent_assignment_type') AS agent_assignment_type,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_days_available') AS INTEGER) AS nbr_days_available,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_hours_available') AS INTEGER) AS nbr_hours_available,
    CAST(GET_JSON_OBJECT(user_properties,'$.login_status') AS BOOLEAN) AS login_status,
    CAST(GET_JSON_OBJECT(event_properties, '$.scheduled_date') AS DATE) AS dt_schedule,
    GET_JSON_OBJECT(event_properties, '$.scheduled_hour_from') AS hour_schedule_started,
    GET_JSON_OBJECT(event_properties, '$.scheduled_hour_to') AS hour_schedule_ended,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '170698'
    AND event_type = 'visit_schedule_clicked'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
