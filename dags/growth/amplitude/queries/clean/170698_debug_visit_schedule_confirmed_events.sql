SELECT
    *,
    GET_JSON_OBJECT(user_properties, '$.gclid') as up_gclid,
    GET_JSON_OBJECT(user_properties, '$.utm_source') as up_utm_source,
    GET_JSON_OBJECT(user_properties, '$.utm_medium') as up_utm_medium,
    GET_JSON_OBJECT(user_properties, '$.utm_campaign') as up_utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.utm_content') as up_utm_content,
    GET_JSON_OBJECT(user_properties, '$.utm_term') as up_utm_term,
    GET_JSON_OBJECT(user_properties, '$.platform') as up_platform,
    GET_JSON_OBJECT(REPLACE(user_properties, '[adjust]', '(adjust)'), '$.(adjust) network') as up_adjust_network,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') as up_entrance_uri,
    GET_JSON_OBJECT(event_properties, '$.house_id') as ep_house_id,
    GET_JSON_OBJECT(event_properties, '$.visit_code') as ep_visit_code
FROM
    datalake_amplitude_clean_staging.170698_debug_visit_schedule_confirmed_events
WHERE
  year={} and month={} and day={}