SELECT
  NULLIF(REGEXP_REPLACE(CAST(response.cdc AS STRING), '[^0-9]', ''), '') AS id_municipal_house,
  'SP' AS state,
  'Osasco' AS city,
  metadata.source AS feed_source,
  metadata.url AS feed_url,
  metadata.accessed_at AS ts_accessed,
  metadata.referer_url AS referer_url,
  crawler_name,
  dt_load,
  year,
  month,
  day
FROM
  datalake_crawled_idactum_houses_raw.sp_osasco_extrato_iptu
