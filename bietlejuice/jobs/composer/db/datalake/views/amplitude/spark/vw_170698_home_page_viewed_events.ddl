DROP VIEW IF EXISTS datalake_amplitude_clean.170698_home_page_viewed_events;
CREATE OR REPLACE VIEW datalake_amplitude_clean.170698_home_page_viewed_events
AS
  SELECT
    *,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_source=([^&|$]+)', 1), ''), 'direct') as up_utm_source,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_medium=([^&|$]+)', 1), ''), 'direct') as up_utm_medium,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_campaign=([^&|$]+)', 1), ''), 'direct') as up_utm_campaign,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_content=([^&|$]+)', 1), ''), 'direct') as up_utm_content,
    coalesce(nullif(regexp_extract(get_json_object(user_properties, '$.entrance_uri'), 'utm_term=([^&|$]+)', 1), ''), 'direct') as up_utm_term,
    get_json_object(event_properties, '$.house_id') as ep_house_id
  FROM
    datalake_amplitude_clean_staging.170698_home_page_viewed_events
;