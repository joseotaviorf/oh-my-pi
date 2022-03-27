SELECT
    *,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') as up_entrance_uri,
    COALESCE(GET_JSON_OBJECT(event_properties, '$.house_id'), GET_JSON_OBJECT(event_properties, '$.Imovel_id')) as ep_house_id,
    GET_JSON_OBJECT(event_properties, '$.business_context') as ep_business_context,
    GET_JSON_OBJECT(user_properties, '$.utm_campaign') as up_utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.utm_medium') as up_utm_medium,
    GET_JSON_OBJECT(user_properties, '$.utm_source') as up_utm_source,
    GET_JSON_OBJECT(user_properties, '$.utm_content') as up_utm_content,
    GET_JSON_OBJECT(user_properties, '$.utm_term') as up_utm_term
FROM
    datalake_amplitude_clean_staging.170698_schedule_page_viewed_events
WHERE
  year={} and month={} and day={} 