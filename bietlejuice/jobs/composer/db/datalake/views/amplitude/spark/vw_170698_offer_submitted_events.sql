DROP VIEW IF EXISTS datalake_amplitude_clean.170698_offer_submitted_events;
CREATE OR REPLACE VIEW datalake_amplitude_clean.170698_offer_submitted_events
AS
    SELECT
        id_user,
        170698 as id_app, -- setting hardcoded because the id_app is wrongly set as null
        cast(trim(get_json_object(event_properties, '$.house_id')) as string) as id_house,
        cast(trim(get_json_object(event_properties, '$.offer_id')) as string) as id_firestore,
        cast(get_json_object(user_properties , '$.platform') as string) as app_type,
        cast(get_json_object(user_properties, '$.utm_source') as string) as utm_source,
        cast(get_json_object(user_properties, '$.utm_medium') as string) as utm_medium,
        cast(get_json_object(user_properties, '$.utm_campaign') as string) as utm_campaign,
        cast(get_json_object(user_properties, '$.utm_content') as string) as utm_content,
        cast(get_json_object(user_properties, '$.utm_term') as string) as utm_term,
        date(ts_event) as dt_event,
        ts_event
    FROM
        datalake_amplitude_clean_staging.170698_offer_submitted_events;