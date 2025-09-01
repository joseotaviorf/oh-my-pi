SELECT
    *,
    get_json_object(user_properties, '$.gclid') AS up_gclid,
    get_json_object(user_properties, '$.utm_source') AS up_utm_source,
    get_json_object(user_properties, '$.utm_medium') AS up_utm_medium,
    get_json_object(user_properties, '$.utm_campaign') AS up_utm_campaign,
    get_json_object(user_properties, '$.utm_content') AS up_utm_content,
    get_json_object(user_properties, '$.utm_term') AS up_utm_term,
    get_json_object(user_properties, '$.platform') AS up_platform,
    get_json_object(replace(user_properties, '[adjust]', '(adjust)'),
                    '$.(adjust) network') AS up_adjust_network,
    get_json_object(user_properties, '$.entrance_uri') AS up_entrance_uri,
    get_json_object(event_properties, '$.house_id') AS ep_house_id,
    get_json_object(event_properties, '$.visit_code') AS ep_visit_code,
    get_json_object(event_properties, '$.business_context') AS ep_business_context
FROM
    datalake_amplitude_clean.events
WHERE
    id_app = '170698' AND event_type = 'visit_schedule_confirmed'
    AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
