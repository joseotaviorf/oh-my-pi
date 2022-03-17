SELECT
    *,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') as up_entrance_uri,
    COALESCE(GET_JSON_OBJECT(event_properties, '$.house_id'), GET_JSON_OBJECT(event_properties, '$.Imovel_id')) as ep_house_id,
    GET_JSON_OBJECT(event_properties, '$.business_context') as ep_business_context
FROM
    datalake_amplitude_clean_staging.170698_schedule_page_viewed_events
WHERE
  year={} and month={} and day={}