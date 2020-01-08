CREATE OR REPLACE VIEW datalake_amplitude_clean_prod."170698_schedule_page_viewed_events" AS
    SELECT
        *,
        json_extract_scalar(user_properties, '$["entrance_uri"]') as up_entrance_uri,
        coalesce(
            json_extract_scalar(event_properties, '$["house_id"]'),
            json_extract_scalar(event_properties, '$["Imovel_id"]')
        ) as ep_house_id,
        json_extract_scalar(event_properties, '$["business_context"]') as ep_business_context
    FROM
        datalake_amplitude_clean_staging_prod."170698_schedule_page_viewed_events";
