CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_visit_intent_clicked_events" AS
    SELECT
        *,
        coalesce(json_extract_scalar(event_properties, '$["house_id"]'), json_extract_scalar(event_properties, '$["houseId"]')) as ep_house_id,
        coalesce(json_extract_scalar(event_properties, '$["dom_performance"]'), json_extract_scalar(event_properties, '$["domPerformance"]')) as ep_dom_performance,
        coalesce(json_extract_scalar(event_properties, '$["network_performance"]'), json_extract_scalar(event_properties, '$["networkPerformance"]')) as ep_network_performance
    FROM
        datalake_amplitude_clean_staging_prod."170698_visit_intent_clicked_events";
