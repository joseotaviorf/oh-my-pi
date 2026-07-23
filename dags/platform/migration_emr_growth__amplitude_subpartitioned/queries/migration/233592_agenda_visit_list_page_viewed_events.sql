SELECT
    id_user,
    GET_JSON_OBJECT(event_properties, '$.is_agenda_extra_visits_shortcut_entrypoint_enabled') AS is_agenda_extra_visits_shortcut_entrypoint_enabled,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 233592
    AND event_type = 'agenda_visit_list_page_viewed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
