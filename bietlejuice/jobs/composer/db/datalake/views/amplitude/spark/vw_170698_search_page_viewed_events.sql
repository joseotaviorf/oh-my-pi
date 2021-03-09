DROP VIEW IF EXISTS datalake_amplitude_clean.170698_search_page_viewed_events;
CREATE OR REPLACE VIEW datalake_amplitude_clean.170698_search_page_viewed_events AS
SELECT
  id_user,
  id_device,
  GET_JSON_OBJECT(event_properties, '$.house_id') AS id_house,
  GET_JSON_OBJECT(event_properties, '$.business_context') AS business_context,
  GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
  GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
  GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
  GET_JSON_OBJECT(user_properties, '$.utm_term') AS utm_term,
  GET_JSON_OBJECT(user_properties, '$.utm_content') AS utm_content,
  GET_JSON_OBJECT(user_properties , '$.platform') AS up_platform,
  CASE WHEN GET_JSON_OBJECT(event_properties , '$.top5_house_id') <> '[]'
    THEN SPLIT(REGEXP_REPLACE(GET_JSON_OBJECT(event_properties , '$.top5_house_id'), '\\[|\\]|\\"', ''), ',')
    ELSE NULL
  END AS top5_house_id,
  year,
  month,
  day,
  ts_event
FROM
  datalake_amplitude_clean_staging.170698_search_page_viewed_events