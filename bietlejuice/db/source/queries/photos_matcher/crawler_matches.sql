SELECT
  "id",
  "crawled_listing_id",
  "sk_house_listing",
  "match",
  "dt_created"
FROM crawler_matches
WHERE "dt_created"::DATE = CURRENT_DATE
;
