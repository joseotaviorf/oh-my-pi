SELECT
    *,
    CAST(GET_JSON_OBJECT(event_properties, '$.formfield_lead_id') AS STRING) AS id_lead_ebdb,
    CAST(GET_JSON_OBJECT(user_properties, '$.initial_utm_campaign') AS STRING) AS initial_utm_campaign,
    CAST(GET_JSON_OBJECT(user_properties, '$.initial_utm_medium') AS STRING) AS initial_utm_medium,
    CAST(GET_JSON_OBJECT(user_properties, '$.initial_utm_source') AS STRING) AS initial_utm_source,
    CAST(GET_JSON_OBJECT(user_properties, '$.initial_utm_content') AS STRING) AS initial_utm_content,
    CAST(GET_JSON_OBJECT(user_properties, '$.initial_utm_term') AS STRING) AS initial_utm_term,
    CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING) AS utm_campaign,
    CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS STRING) AS utm_medium,
    CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS STRING) AS utm_source,
    CAST(GET_JSON_OBJECT(user_properties, '$.utm_content') AS STRING) AS utm_content,
    CAST(GET_JSON_OBJECT(user_properties, '$.utm_term') AS STRING) AS utm_term,
    CAST(GET_JSON_OBJECT(user_properties , '$.platform') AS STRING) AS app_type,
    CAST(GET_JSON_OBJECT(user_properties , '$.referring_domain') AS STRING) AS referring_domain,
    CAST(TRIM(GET_JSON_OBJECT(event_properties, '$.formfield_lead_uuid')) AS STRING) AS formfield_lead_uuid,
    CAST(GET_JSON_OBJECT(user_properties, '$.country') AS STRING) AS country_code
FROM
    datalake_amplitude_new_clean.events
WHERE
    id_app = '183047' AND event_type = 'price_suggestion_sale_form_submitted'
