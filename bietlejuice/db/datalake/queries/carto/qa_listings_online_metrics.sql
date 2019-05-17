SELECT fh.sk_house_listing,
       COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'listing_page_viewed' THEN evt.uuid END) AS "listing_page_viewed",
       COUNT(DISTINCT CASE WHEN TRIM(evt.et) = 'schedule_page_viewed' THEN evt.uuid END) AS "schedule_page_viewed"
FROM datalake_clean.amplitude_events evt
LEFT JOIN datalake_clean.ods_fact_house_listings fh ON SUBSTRING(fh.sk_house_listing,1,9) = e_house_id
WHERE TRIM(ym) >= '2018-12'
  AND TRIM(app) = '170698'
GROUP BY 1
