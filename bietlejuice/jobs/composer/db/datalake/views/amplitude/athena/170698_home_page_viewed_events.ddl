CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_home_page_viewed_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["entrance_uri"]') as up_entrance_uri
    FROM
        datalake_amplitude_clean_staging_prod."170698_home_page_viewed_events";
