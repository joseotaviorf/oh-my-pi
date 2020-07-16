CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_visit_hoursalert_confirmed_events" AS
    SELECT
        *,
        json_extract_scalar(event_properties, '$["house_id"]') as ep_house_id,
        json_extract_scalar(event_properties, '$["alert_target_date"]') as ep_alert_target_date,
        json_extract_scalar(event_properties, '$["alert_slot_from"]') as ep_alert_slot_from,
        json_extract_scalar(event_properties, '$["alert_slot_to"]') as ep_alert_slot_to
    FROM
        datalake_amplitude_clean_staging_prod."170698_visit_hoursalert_confirmed_events";
