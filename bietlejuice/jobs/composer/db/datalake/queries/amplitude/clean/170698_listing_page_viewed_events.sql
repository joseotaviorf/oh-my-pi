SELECT
    *,
    GET_JSON_OBJECT(user_properties, '$.entrance_uri') as up_entrance_uri,
    GET_JSON_OBJECT(event_properties, '$.house_id') as ep_house_id
FROM
    datalake_amplitude_clean_staging.170698_listing_page_viewed_events
WHERE
  year={} and month={} and day={}