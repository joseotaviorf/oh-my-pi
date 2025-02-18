SELECT 
  id,
  type,
  name,
  variable,
  NOW() AS ts_load
FROM datalake_legaut_raw.crawlers_crawlerkeytype