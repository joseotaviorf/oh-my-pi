SELECT
    GET_JSON_OBJECT(event_properties, '$.alert_id') AS alert_id,
    *,
    GET_JSON_OBJECT(event_properties, '$.business_context') AS business_context,
    GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
    GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
    GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.utm_term') AS utm_term,
    GET_JSON_OBJECT(user_properties, '$.utm_content') AS utm_content,
    GET_JSON_OBJECT(user_properties , '$.platform') AS up_platform,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') AS entrance_uri,
    GET_JSON_OBJECT(user_properties, '$.referrer') AS referrer
FROM
    datalake_amplitude_clean_staging.170698_homes_subscription_confirmed_events
WHERE
  year={} and month={} and day={}
