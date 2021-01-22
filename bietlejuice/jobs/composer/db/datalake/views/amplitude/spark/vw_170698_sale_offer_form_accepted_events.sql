DROP VIEW IF EXISTS datalake_amplitude_clean.170698_sale_offer_form_accepted_events;
CREATE OR REPLACE VIEW datalake_amplitude_clean.170698_sale_offer_form_accepted_events
AS
    SELECT
        id_user,
        id_app,
        TRIM(GET_JSON_OBJECT(event_properties, '$.house_id')) AS id_house,
        TRIM(GET_JSON_OBJECT(event_properties, '$.offer_id')) AS id_offer,
        GET_JSON_OBJECT(user_properties , '$.platform') AS app_type,
        GET_JSON_OBJECT(user_properties, '$.utm_source') AS utm_source,
        GET_JSON_OBJECT(user_properties, '$.utm_medium') AS utm_medium,
        GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS utm_campaign,
        GET_JSON_OBJECT(user_properties, '$.utm_content') AS utm_content,
        GET_JSON_OBJECT(user_properties, '$.utm_term') AS utm_term,
        ts_event
    FROM
        datalake_amplitude_clean_staging.170698_sale_offer_form_accepted_events;