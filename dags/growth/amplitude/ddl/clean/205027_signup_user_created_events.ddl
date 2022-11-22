CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."205027_signup_user_created_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["utm_source"]') as up_utm_source,
        json_extract_scalar(user_properties, '$["utm_medium"]') as up_utm_medium,
        json_extract_scalar(user_properties, '$["utm_campaign"]') as up_utm_campaign,
        json_extract_scalar(user_properties, '$["utm_content"]') as up_utm_content,
        json_extract_scalar(user_properties, '$["utm_term"]') as up_utm_term,
        json_extract_scalar(user_properties, '$["platform"]') as up_platform
    FROM
        datalake_amplitude_clean_staging_prod."205027_signup_user_created_events";
