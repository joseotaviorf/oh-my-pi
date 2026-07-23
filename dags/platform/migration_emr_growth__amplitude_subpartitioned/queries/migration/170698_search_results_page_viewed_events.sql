SELECT
  id_amplitude,
  ids_amplitude_attributed,
  id_user,
  id_device,
  id_event,
  id_app,
  uuid,
  adid,
  id_session,
  id_schema,
  id_inserted,
  idfa,
  CAST(GET_JSON_OBJECT(event_properties, house_id) AS STRING) AS ep_house_id,
  CAST(GET_JSON_OBJECT(user_properties, ab_beakman_native_demand_property_card_toggle) AS STRING) AS up_ab_beakman_native_demand_property_card_toggle,
  GET_JSON_OBJECT(event_properties, search_id) AS id_search,
  TRANSFORM(
    FROM_JSON(GET_JSON_OBJECT(event_properties, search_results_list), 'array<string>'),
    x -> CAST(X AS BIGINT)
  ) AS ids_search_results_list,
  event_type,
  amplitude_event_type,
  city,
  country,
  data,
  device_brand,
  device_carrier,
  device_family,
  device_manufacturer,
  device_model,
  device_type,
  dma,
  ip_address,
  location_lat,
  location_lng,
  os_name,
  os_version,
  platform,
  library,
  region,
  start_version,
  language,
  version_name,
  sample_rate,
  event_properties,
  user_properties,
  CAST(GET_JSON_OBJECT(event_properties, business_context) AS STRING) AS business_context,
  CAST(GET_JSON_OBJECT(event_properties, search_context) AS STRING) AS search_context,
  CAST(GET_JSON_OBJECT(event_properties, search_query_context) AS STRING) AS search_query_context,
  CAST(GET_JSON_OBJECT(event_properties, uri) AS STRING) AS uri,
  REGEXP_EXTRACT(GET_JSON_OBJECT(event_properties, uri), '\\/imovel\\/([^\\/|\\?]+)') AS search_location_slug,
  CAST(GET_JSON_OBJECT(event_properties, view_mode) AS STRING) AS view_mode,
  CAST(GET_JSON_OBJECT(event_properties, sort_order) AS STRING) AS sort_order,
  CAST(GET_JSON_OBJECT(user_properties, utm_source) AS STRING) AS utm_source,
  CAST(GET_JSON_OBJECT(user_properties, utm_medium) AS STRING) AS utm_medium,
  CAST(GET_JSON_OBJECT(user_properties, utm_campaign) AS STRING) AS utm_campaign,
  CAST(GET_JSON_OBJECT(user_properties, utm_term) AS STRING) AS utm_term,
  CAST(GET_JSON_OBJECT(user_properties, utm_content) AS STRING) AS utm_content,
  CAST(GET_JSON_OBJECT(user_properties, platform) AS STRING) AS up_platform,
  CAST(GET_JSON_OBJECT(user_properties, entrance_uri) AS STRING) AS entrance_uri,
  CAST(GET_JSON_OBJECT(user_properties, referrer) AS STRING) AS referrer,
  COALESCE(
    NULLIF(
      REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, entrance_uri), 'utm_source=([^&|$]+)'),
      ''
    ),
    'direct'
  ) AS up_utm_source,
  COALESCE(
    NULLIF(
      REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, entrance_uri), 'utm_medium=([^&|$]+)'),
      ''
    ),
    'direct'
  ) AS up_utm_medium,
  COALESCE(
    NULLIF(
      REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, entrance_uri), 'utm_campaign=([^&|$]+)'),
      ''
    ),
    'direct'
  ) AS up_utm_campaign,
  COALESCE(
    NULLIF(
      REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, entrance_uri), 'utm_content=([^&|$]+)'),
      ''
    ),
    'direct'
  ) AS up_utm_content,
  COALESCE(
    NULLIF(
      REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, entrance_uri), 'utm_term=([^&|$]+)'),
      ''
    ),
    'direct'
  ) AS up_utm_term,
  CASE
    WHEN GET_JSON_OBJECT(event_properties, top5_house_id) <> '[]'
    THEN SPLIT(
      REGEXP_REPLACE(GET_JSON_OBJECT(event_properties, top5_house_id), '\\[|\\]|\\"', ''),
      ','
    )
    ELSE NULL
  END AS top5_house_id,
  CAST(GET_JSON_OBJECT(event_properties, nbr_listed_classifieds) AS INT) AS nbr_listed_classifieds,
  CAST(GET_JSON_OBJECT(event_properties, nbr_search_results) AS INT) AS nbr_search_results,
  CAST(GET_JSON_OBJECT(event_properties, nbr_search_classifieds) AS INT) AS nbr_search_classifieds,
  CAST(GET_JSON_OBJECT(event_properties, nbr_search_transactional) AS INT) AS nbr_search_transactional,
  CASE WHEN nbr_listed_classifieds > 0 THEN TRUE ELSE FALSE END AS is_qac,
  CASE WHEN nbr_search_classifieds > 0 THEN TRUE ELSE FALSE END AS is_qac_region,
  is_paying,
  is_attribution_event,
  ts_server_received,
  ts_event,
  ts_server_uploaded,
  ts_user_created,
  ts_client_event,
  ts_client_uploaded,
  ts_processed,
  year,
  month,
  day
FROM datalake_amplitude_clean.events
WHERE
  id_app = '170698'
  AND event_type = 'search_results_page_viewed'
  AND MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
