CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_listing_page_viewed_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["entrance_uri"]') as up_entrance_uri,
        json_extract_scalar(event_properties, '$["house_id"]') as ep_house_id
    FROM
        datalake_amplitude_clean_staging_prod."170698_listing_page_viewed_events";
