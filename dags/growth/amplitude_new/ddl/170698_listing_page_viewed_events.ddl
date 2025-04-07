SELECT
    GET_JSON_OBJECT(event_properties, '$.house_id') AS ep_house_id,
    *,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') AS up_utm_source,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') AS up_utm_medium,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') AS up_utm_campaign,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') AS up_utm_content,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') AS up_utm_term,
    GET_JSON_OBJECT(event_properties, "$['listing_rent_model.rentalAdministrator']") AS ep_listing_rent_model_rentaladministrator,
    GET_JSON_OBJECT(event_properties, '$.business_context') AS business_context,
    GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
    GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
    GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
    GET_JSON_OBJECT(user_properties, '$.utm_term') AS utm_term,
    GET_JSON_OBJECT(user_properties, '$.utm_content') AS utm_content,
    GET_JSON_OBJECT(user_properties , '$.platform') AS up_platform,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') AS entrance_uri,
    GET_JSON_OBJECT(user_properties, '$.referrer') AS referrer,
    CASE WHEN GET_JSON_OBJECT(event_properties , '$.top5_house_id') <> '[]'
      THEN SPLIT(REGEXP_REPLACE(GET_JSON_OBJECT(event_properties , '$.top5_house_id'), '\\[|\\]|\\"', ''), ',')
      ELSE NULL
    END AS top5_house_id
FROM
    datalake_amplitude_new_clean.events
WHERE
  id_app = '170698' AND event_type = 'listing_page_viewed'
