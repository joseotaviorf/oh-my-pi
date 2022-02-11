CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_debug_visit_schedule_confirmed_events" AS
    SELECT
        *,
        JSON_EXTRACT_SCALAR(user_properties, '$["gclid"]') as up_gclid,
        JSON_EXTRACT_SCALAR(user_properties, '$["utm_source"]') as up_utm_source,
        JSON_EXTRACT_SCALAR(user_properties, '$["utm_medium"]') as up_utm_medium,
        JSON_EXTRACT_SCALAR(user_properties, '$["utm_campaign"]') as up_utm_campaign,
        JSON_EXTRACT_SCALAR(user_properties, '$["utm_content"]') as up_utm_content,
        JSON_EXTRACT_SCALAR(user_properties, '$["utm_term"]') as up_utm_term,
        JSON_EXTRACT_SCALAR(user_properties, '$["platform"]') as up_platform,
        JSON_EXTRACT_SCALAR(user_properties, '$["[adjust] network"]') as up_adjust_network,
        JSON_EXTRACT_SCALAR(user_properties, '$["entrance_uri"]') as up_entrance_uri,
        JSON_EXTRACT_SCALAR(event_properties, '$["house_id"]') as ep_house_id,
        JSON_EXTRACT_SCALAR(event_properties, '$["visit_code"]') as ep_visit_code
    FROM
        datalake_amplitude_clean_staging_prod."170698_debug_visit_schedule_confirmed_events";
