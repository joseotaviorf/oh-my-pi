SELECT
    *,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') as up_entrance_uri,
    GET_JSON_OBJECT(event_properties, '$.search_dropdown_value') as ep_search_dropdown_value,
    GET_JSON_OBJECT(event_properties, '$.filter_value_valor_type') as ep_filter_value_valor_type,
    GET_JSON_OBJECT(event_properties, '$.filter_value_valor_min') as ep_filter_value_valor_min,
    GET_JSON_OBJECT(event_properties, '$.filter_value_valor_max') as ep_filter_value_valor_max,
    GET_JSON_OBJECT(event_properties, '$.filter_value_furnished') as ep_filter_value_furnished,
    GET_JSON_OBJECT(event_properties, '$.filter_value_metro') as ep_filter_value_metro,
    CAST(GET_JSON_OBJECT(event_properties, '$.filter_list_rooms') AS STRING) as ep_filter_list_rooms,
    CAST(GET_JSON_OBJECT(event_properties, '$.filter_list_apartment') AS STRING) as ep_filter_list_apartment,
    CAST(GET_JSON_OBJECT(event_properties, '$.search_results_list') AS STRING) as ep_search_results_list,
    GET_JSON_OBJECT(event_properties, '$.house_id') as ep_house_id,
    GET_JSON_OBJECT(user_properties, '$.ab_search_ranking') as up_ab_search_ranking
FROM
    datalake_amplitude_clean_staging.170698_search_results_page_viewed_events
where
  year={} and month={} and day={}