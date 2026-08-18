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
    datalake_crawled_idactum_houses_raw.bsb_main_debitos
)
SELECT
  item.Imovel AS id_municipal_house,
  item.Imovel AS municipal_inscription,
  'DF' AS state,
  'Brasilia' AS city,
  item.DarEndereco AS address_details,
  CAST(item.DarValorPrincipal AS DOUBLE) AS assessed_iptu_value,
  item.DesricaoReceita AS usage_purpose,
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
WHERE
  item.Imovel IS NOT NULL
