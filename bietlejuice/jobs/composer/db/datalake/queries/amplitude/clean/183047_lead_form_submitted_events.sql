SELECT
    *,
    GET_JSON_OBJECT(user_properties, '$.initial_utm_campaign.') as up_initial_utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.initial_utm_medium') as up_initial_utm_medium,
    GET_JSON_OBJECT(user_properties, '$.initial_utm_source') as up_initial_utm_source,
    GET_JSON_OBJECT(user_properties, '$.initial_utm_content') as up_initial_utm_content,
    GET_JSON_OBJECT(user_properties, '$.initial_utm_term') as up_initial_utm_term,
    GET_JSON_OBJECT(user_properties, '$.utm_campaign') as up_utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.utm_medium') as up_utm_medium,
    GET_JSON_OBJECT(user_properties, '$.utm_source') as up_utm_source,
    GET_JSON_OBJECT(user_properties, '$.utm_content') as up_utm_content,
    GET_JSON_OBJECT(user_properties, '$.utm_term') as up_utm_term,
    GET_JSON_OBJECT(user_properties, '$.platform') as up_platform,
    GET_JSON_OBJECT(user_properties, '$.referring_domain') as up_referring_domain,
    GET_JSON_OBJECT(event_properties, '$.formfield_lead_uuid') as ep_formfield_lead_uuid
FROM
    datalake_amplitude_clean_staging.183047_lead_form_submitted_events
WHERE
  year={} and month={} and day={}