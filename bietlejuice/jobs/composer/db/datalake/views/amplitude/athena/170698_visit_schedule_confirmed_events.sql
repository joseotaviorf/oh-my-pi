CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_visit_schedule_confirmed_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["gclid"]') as up_gclid,
        json_extract_scalar(user_properties, '$["utm_source"]') as up_utm_source,
        json_extract_scalar(user_properties, '$["utm_medium"]') as up_utm_medium,
        json_extract_scalar(user_properties, '$["utm_campaign"]') as up_utm_campaign,
        json_extract_scalar(user_properties, '$["utm_content"]') as up_utm_content,
        json_extract_scalar(user_properties, '$["utm_term"]') as up_utm_term,
        json_extract_scalar(user_properties, '$["platform"]') as up_platform,
        json_extract_scalar(user_properties, '$["[adjust] network"]') as up_adjust_network,
        json_extract_scalar(user_properties, '$["entrance_uri"]') as up_entrance_uri,
        json_extract_scalar(event_properties, '$["house_id"]') as ep_house_id,
        json_extract_scalar(event_properties, '$["visit_code"]') as ep_visit_code
    FROM
        datalake_amplitude_clean_staging_prod."170698_visit_schedule_confirmed_events";
