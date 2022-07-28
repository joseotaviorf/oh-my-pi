DROP VIEW IF EXISTS datalake_amplitude_clean.205027_referral_form_accepted_events;
CREATE OR REPLACE VIEW datalake_amplitude_clean.205027_referral_form_accepted_events
AS
    SELECT
        *,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING) AS utm_campaign,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS STRING) AS utm_medium,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS STRING) AS utm_source,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_content') AS STRING) AS utm_content,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_term') AS STRING) AS utm_term,
        CAST(GET_JSON_OBJECT(user_properties , '$.platform') AS STRING) AS app_type,
        CAST(GET_JSON_OBJECT(user_properties , '$.referring_domain') AS STRING) AS referring_domain,
        CAST(TRIM(GET_JSON_OBJECT(event_properties, '$.lead_id')) AS STRING) AS id_lead
    FROM
        datalake_amplitude_clean_staging.205027_referral_form_accepted_events;