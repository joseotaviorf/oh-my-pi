WITH
listing_page_viewed AS (
  SELECT
  	DATE_TRUNC('week', CAST(regexp_extract(TRIM(evt.event_time), '(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})', 1) AS TIMESTAMP)) AS event_timestamp,
  	TRIM(evt.e_house_id) AS house_id,
    COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'listing_page_viewed' THEN evt.uuid END) AS listing_page_views,
    COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'schedule_page_viewed' THEN evt.uuid END) AS schedule_page_views
  FROM datalake_clean.amplitude_events evt
  	WHERE TRIM(evt.et) IN ('listing_page_viewed', 'schedule_page_viewed')
  	AND TRIM(app) = '170698'
  	AND ym >= '2019-05'
  GROUP BY 1, 2
),
general_info AS (
  SELECT
      dhl.sk_house_listing,
      dhl.id_house
  FROM datalake_clean.ods_dim_house_listing dhl
  WHERE dhl.ts_publication <> ''
)
SELECT
  gi.sk_house_listing,
  date_trunc('week', lpv.event_timestamp) AS date_period,
  listing_page_views,
  schedule_page_views
FROM listing_page_viewed lpv
JOIN general_info gi
  ON lpv.house_id = gi.id_house
WHERE event_timestamp >= DATE_ADD('week', -2, CURRENT_DATE) OR DATE_TRUNC('week', event_timestamp) = DATE_TRUNC('week', CURRENT_DATE)
