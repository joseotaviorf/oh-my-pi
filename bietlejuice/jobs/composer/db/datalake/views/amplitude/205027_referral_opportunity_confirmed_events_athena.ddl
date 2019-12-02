CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."205027_referral_opportunity_confirmed_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["initial_utm_campaign"]') as up_initial_utm_campaign,
        json_extract_scalar(user_properties, '$["initial_utm_medium"]') as up_initial_utm_medium,
        json_extract_scalar(user_properties, '$["initial_utm_source"]') as up_initial_utm_source,
        json_extract_scalar(user_properties, '$["initial_utm_content"]') as up_initial_utm_content,
        json_extract_scalar(user_properties, '$["initial_utm_term"]') as up_initial_utm_term,
        json_extract_scalar(user_properties, '$["platform"]') as up_platform,
        json_extract_scalar(user_properties, '$["referring_domain"]') as up_referring_domain,
        json_extract_scalar(event_properties, '$["lead_id"]') as ep_lead_id
    FROM
        datalake_amplitude_clean_staging_prod."205027_referral_opportunity_confirmed_events";
