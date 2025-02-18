SELECT 
  id,
  crawler_id AS id_crawler,
  crawlergroup_id AS id_crawler_group,
  suggestiongroup_id AS id_suggestion_group,
  value,
  type,
  NOW() AS ts_load
FROM datalake_legaut_raw.crawlers_crawlerkey