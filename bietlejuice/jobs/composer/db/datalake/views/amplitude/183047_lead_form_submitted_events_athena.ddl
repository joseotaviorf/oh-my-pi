CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."183047_lead_form_submitted_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["initial_utm_campaign"]') as up_initial_utm_campaign,
        json_extract_scalar(user_properties, '$["initial_utm_medium"]') as up_initial_utm_medium,
        json_extract_scalar(user_properties, '$["initial_utm_source"]') as up_initial_utm_source,
        json_extract_scalar(user_properties, '$["initial_utm_content"]') as up_initial_utm_content,
        json_extract_scalar(user_properties, '$["initial_utm_term"]') as up_initial_utm_term,
        json_extract_scalar(user_properties, '$["utm_campaign"]') as up_utm_campaign,
        json_extract_scalar(user_properties, '$["utm_medium"]') as up_utm_medium,
        json_extract_scalar(user_properties, '$["utm_source"]') as up_utm_source,
        json_extract_scalar(user_properties, '$["utm_content"]') as up_utm_content,
        json_extract_scalar(user_properties, '$["utm_term"]') as up_utm_term,
        json_extract_scalar(user_properties, '$["platform"]') as up_platform,
        json_extract_scalar(user_properties, '$["referring_domain"]') as up_referring_domain,
        json_extract_scalar(event_properties, '$["formfield_lead_uuid"]') as ep_formfield_lead_uuid
    FROM
        datalake_amplitude_clean_staging_prod."183047_lead_form_submitted_events";
