SELECT
    *,
    get_json_object(user_properties, '$.gclid') as up_gclid,
    get_json_object(user_properties, '$.utm_source') as up_utm_source,
    get_json_object(user_properties, '$.utm_medium') as up_utm_medium,
    get_json_object(user_properties, '$.utm_campaign') as up_utm_campaign,
    get_json_object(user_properties, '$.utm_content') as up_utm_content,
    get_json_object(user_properties, '$.utm_term') as up_utm_term,
    get_json_object(user_properties, '$.platform') as up_platform,
    get_json_object(replace(user_properties, '[adjust]', '(adjust)'),
                    '$.(adjust) network') as up_adjust_network,
    get_json_object(user_properties, '$.entrance_uri') as up_entrance_uri,
    get_json_object(event_properties, '$.house_id') as ep_house_id,
    get_json_object(event_properties, '$.visit_code') as ep_visit_code
FROM
    datalake_amplitude_new_clean.events
WHERE
  id_app = '170698' AND event_type = 'visit_schedule_confirmed'
