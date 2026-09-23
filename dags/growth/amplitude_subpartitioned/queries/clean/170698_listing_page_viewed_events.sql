SELECT
    GET_JSON_OBJECT(event_properties, '$.house_id') AS ep_house_id,
    CAST(GET_JSON_OBJECT(event_properties, '$.sub_region_id') AS INTEGER) AS id_region,
    *,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') AS up_utm_source,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') AS up_utm_medium,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') AS up_utm_campaign,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') AS up_utm_content,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') AS up_utm_term,
    GET_JSON_OBJECT(event_properties, "$['listing_rent_model.rentalAdministrator']") AS ep_listing_rent_model_rentaladministrator,
    LOWER(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
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
    END AS top5_house_id,
    CAST(GET_JSON_OBJECT(event_properties, '$.uri') AS STRING) AS uri,
    COALESCE(CAST(GET_JSON_OBJECT(event_properties, '$.is_qac') AS BOOLEAN), FALSE) AS is_qac,
    is_qac AS is_qac_region,
    CASE GET_JSON_OBJECT(user_properties, '$.isMoraEnabledOnApp')
        WHEN 'true' THEN TRUE
        WHEN 'false' THEN FALSE
    END AS up_is_mora_enabled_on_app,
    GET_JSON_OBJECT(event_properties, '$.visit_status') AS visit_status,
    CAST(GET_JSON_OBJECT(event_properties, '$.valor_aluguel') AS BIGINT) AS rent_value,
    CAST(GET_JSON_OBJECT(event_properties, '$.valor_condominio') AS BIGINT) AS condo_value,
    CAST(GET_JSON_OBJECT(event_properties, '$.valor_total') AS BIGINT) AS total_value,
    CAST(GET_JSON_OBJECT(event_properties, '$.valor_venda') AS BIGINT) AS sale_value
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = '170698' AND event_type = 'listing_page_viewed'
    AND year = {year} AND month = {month} AND day = {day}
