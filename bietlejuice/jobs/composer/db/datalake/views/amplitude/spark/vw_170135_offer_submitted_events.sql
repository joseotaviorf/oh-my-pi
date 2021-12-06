DROP VIEW IF EXISTS datalake_amplitude_clean.170135_offer_submitted_events;
CREATE OR REPLACE VIEW datalake_amplitude_clean.170135_offer_submitted_events
AS
    SELECT
        id_user,
        170135 AS id_app, -- setting hardcoded because the id_app is wrongly set as null
        STRING(TRIM(GET_JSON_OBJECT(event_properties, '$.house_id'))) AS id_house,
        STRING(TRIM(COALESCE(
            GET_JSON_OBJECT(event_properties, '$.offer_id'),
            REGEXP_EXTRACT(GET_JSON_OBJECT(event_properties, '$.uri'),'(?<=\/(offer|aluguel)\/).*(?=\/)', 0)
        ))) AS id_firestore,
        STRING(GET_JSON_OBJECT(user_properties, '$.platform')) AS app_type,
        STRING(GET_JSON_OBJECT(user_properties, '$.utm_source')) AS utm_source,
        STRING(GET_JSON_OBJECT(user_properties, '$.utm_medium')) AS utm_medium,
        STRING(GET_JSON_OBJECT(user_properties, '$.utm_campaign')) AS utm_campaign,
        STRING(GET_JSON_OBJECT(user_properties, '$.utm_content')) AS utm_content,
        STRING(GET_JSON_OBJECT(user_properties, '$.utm_term')) AS utm_term,
        DATE(ts_event) AS dt_event,
        ts_event
    FROM
        datalake_amplitude_clean_staging.170135_offer_submitted_events;