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
    STRING(GET_JSON_OBJECT(event_properties, '$.house_id')) AS ep_house_id,
    STRING(GET_JSON_OBJECT(user_properties, '$.ab_beakman_native_demand_property_card_toggle')) AS up_ab_beakman_native_demand_property_card_toggle,
    GET_JSON_OBJECT(event_properties, '$.search_id') AS id_search,
    TRANSFORM(FROM_JSON(GET_JSON_OBJECT(event_properties, '$.search_results_list'), 'array<string>'), x -> CAST(X AS BIGINT)) AS ids_search_results_list,
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
    STRING(GET_JSON_OBJECT(event_properties, '$.business_context')) AS business_context,
    STRING(GET_JSON_OBJECT(event_properties, '$.search_context')) AS search_context,
    STRING(GET_JSON_OBJECT(event_properties, '$.search_query_context')) AS search_query_context,
    STRING(GET_JSON_OBJECT(event_properties, '$.uri')) AS uri,
    REGEXP_EXTRACT(GET_JSON_OBJECT(event_properties, '$.uri'), '\/imovel\/([^\/|\?]+)', 1) AS search_location_slug,
    STRING(GET_JSON_OBJECT(event_properties, '$.view_mode')) AS view_mode,
    STRING(GET_JSON_OBJECT(event_properties, '$.sort_order')) AS sort_order,
    STRING(GET_JSON_OBJECT(user_properties, '$.utm_source')) AS utm_source,
    STRING(GET_JSON_OBJECT(user_properties, '$.utm_medium')) AS utm_medium,
    STRING(GET_JSON_OBJECT(user_properties, '$.utm_campaign')) AS utm_campaign,
    STRING(GET_JSON_OBJECT(user_properties, '$.utm_term')) AS utm_term,
    STRING(GET_JSON_OBJECT(user_properties, '$.utm_content')) AS utm_content,
    STRING(GET_JSON_OBJECT(user_properties , '$.platform')) AS up_platform,
    STRING(GET_JSON_OBJECT(user_properties, '$.entrance_uri')) AS entrance_uri,
    STRING(GET_JSON_OBJECT(user_properties, '$.referrer')) AS referrer,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') AS up_utm_source,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') AS up_utm_medium,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') AS up_utm_campaign,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') AS up_utm_content,
    COALESCE(NULLIF(REGEXP_EXTRACT(GET_JSON_OBJECT(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') AS up_utm_term,
    CASE
        WHEN GET_JSON_OBJECT(event_properties , '$.top5_house_id') <> '[]'
            THEN SPLIT(REGEXP_REPLACE(GET_JSON_OBJECT(event_properties , '$.top5_house_id'), '\\[|\\]|\\"', ''), ',')
        ELSE NULL
    END AS top5_house_id,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_listed_classifieds') AS INTEGER) AS nbr_listed_classifieds,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_search_results') AS INTEGER) AS nbr_search_results,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_search_classifieds') AS INTEGER) AS nbr_search_classifieds,
    CAST(GET_JSON_OBJECT(event_properties, '$.nbr_search_transactional') AS INTEGER) AS nbr_search_transactional,
    CASE
        WHEN nbr_listed_classifieds > 0 THEN True 
        ELSE False 
    END AS is_qac,
    CASE 
        WHEN nbr_search_classifieds > 0 THEN True 
        ELSE False 
    END AS is_qac_region,
    CASE GET_JSON_OBJECT(user_properties, '$.isMoraEnabledOnApp')
        WHEN 'true' THEN TRUE
        WHEN 'false' THEN FALSE
    END AS up_is_mora_enabled_on_app,
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
FROM
    datalake_amplitude_events_clean.events
WHERE
    id_app = '170698' AND event_type = 'search_results_page_viewed'
    AND year = {year} AND month = {month} AND day = {day}
