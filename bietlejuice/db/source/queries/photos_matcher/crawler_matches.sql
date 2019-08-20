SELECT
  "id",
  "id_crawled_listing",
  "sk_house_listing",
  "match",
  "dt_created"
FROM crawler_matches
WHERE "dt_created"::DATE = ({execution_date})::DATE
;
