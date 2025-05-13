SELECT
        *,
        CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS BIGINT) AS ep_house_id,
        GET_JSON_OBJECT(event_properties, '$.alert_target_date') AS ep_alert_target_date,
        CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.alert_slot_from'), '') AS BIGINT) AS ep_alert_slot_from,
        CAST(COALESCE(GET_JSON_OBJECT(event_properties, '$.alert_slot_to'), '') AS BIGINT) AS ep_alert_slot_to
    FROM
        datalake_amplitude_new_clean.events
    WHERE
    id_app = '170698' AND event_type = 'visit_hoursalert_confirmed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'