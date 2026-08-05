WITH raw AS (
  SELECT
    response,
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
    datalake_crawled_idactum_houses_raw.sp_osasco_pesquisa_cdc
)
SELECT
  COALESCE(item.inscricao, item.cdc) AS id_municipal_house,
  item.inscricao AS municipal_inscription,
  item.cdc AS cdc,
  'SP' AS state,
  'Osasco' AS city,
  item.endereco AS address_details,
  item.no_matricula AS real_estate_registry,
  item.proprietario_compromissario AS owner_name,
  CASE
    WHEN LOWER(TRIM(item.situacao)) = 'ativo' THEN 1.0
    ELSE 0.0
  END AS is_active,
  raw.feed_source,
  raw.feed_url,
  raw.ts_accessed,
  raw.referer_url,
  raw.crawler_name,
  raw.dt_load,
  raw.year,
  raw.month,
  raw.day
FROM
  raw
  LATERAL VIEW OUTER EXPLODE(raw.response) response_exploded AS item
