SELECT
  NULLIF(REGEXP_REPLACE(CAST(response.inscricao AS STRING), '[^0-9]', ''), '') AS id_municipal_house,
  'PE' AS state,
  'Recife' AS city,
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
  datalake_crawled_idactum_houses_raw.pe_recife_certidao_narrativa_imob
