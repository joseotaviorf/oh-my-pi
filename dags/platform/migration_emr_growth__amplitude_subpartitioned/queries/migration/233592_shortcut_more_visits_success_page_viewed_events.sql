SELECT
    CAST(id_user AS BIGINT) AS id_user,
    get_json_object(event_properties, '$.suggestion_house_id') AS ids_suggestion_house,
    get_json_object(event_properties, '$.visit_code') AS visit_code,
    get_json_object(event_properties, '$.visit_status') AS visit_status,
    get_json_object(event_properties, '$.business_context') AS business_context,
    get_json_object(event_properties, '$.current_page') AS current_page,
    CAST(get_json_object(user_properties, '$.isRentAgent') AS BOOLEAN) AS is_rent_agent,
    CAST(get_json_object(user_properties, '$.isSaleAgent') AS BOOLEAN) AS is_sale_agent,
    CAST(get_json_object(user_properties, '$.isSales3P') AS BOOLEAN) AS is_sale_3p,
    CAST(get_json_object(event_properties, '$.suggestion_count') AS INTEGER) AS count_suggestion,
    ts_event,
    year,
    month,
    day
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = 233592
    AND event_type = 'shortcut_more_visits_success_page_viewed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
