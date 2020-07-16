CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_search_results_page_viewed_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["entrance_uri"]') as up_entrance_uri,
        json_extract_scalar(user_properties, '$["ab_search_ranking"]') as up_ab_search_ranking,
        json_extract_scalar(event_properties, '$["search_dropdown_value"]') as ep_search_dropdown_value,
        json_extract_scalar(event_properties, '$["filter_value_valor_type"]') as ep_filter_value_valor_type,
        json_extract_scalar(event_properties, '$["filter_value_valor_min"]') as ep_filter_value_valor_min,
        json_extract_scalar(event_properties, '$["filter_value_valor_max"]') as ep_filter_value_valor_max,
        json_extract_scalar(event_properties, '$["filter_value_furnished"]') as ep_filter_value_furnished,
        json_extract_scalar(event_properties, '$["filter_value_metro"]') as ep_filter_value_metro,
        cast(json_extract(event_properties, '$["filter_list_rooms"]') as ARRAY(VARCHAR)) as ep_filter_list_rooms,
        cast(json_extract(event_properties, '$["filter_list_apartment"]') as ARRAY(VARCHAR)) as ep_filter_list_apartment,
        cast(json_extract(event_properties, '$["search_results_list"]') as ARRAY(VARCHAR)) as ep_search_results_list
    FROM
        datalake_amplitude_clean_staging_prod."170698_search_results_page_viewed_events";
