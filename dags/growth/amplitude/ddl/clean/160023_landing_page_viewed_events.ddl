CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."160023_landing_page_viewed_events" AS
    SELECT
        *,
        json_extract_scalar(event_properties, '$["ub_page_variant"]') as ep_ub_page_variant,
        json_extract_scalar(event_properties, '$["ub_page_name"]') as ep_ub_page_name
    FROM
        datalake_amplitude_clean_staging_prod."160023_landing_page_viewed_events";
