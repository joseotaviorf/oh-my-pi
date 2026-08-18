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
    datalake_crawled_idactum_houses_raw.bsb_main_pauta
)
SELECT
  COALESCE(item.InscricaoImovel, raw.response.infos_imovel.InscricaoImovel) AS id_municipal_house,
  COALESCE(item.InscricaoImovel, raw.response.infos_imovel.InscricaoImovel) AS municipal_inscription,
  'DF' AS state,
  'Brasilia' AS city,
  raw.response.infos_imovel.Endereco AS address_details,
  CASE
    WHEN item.BCIPTU IS NULL OR TRIM(item.BCIPTU) = '' THEN NULL
    ELSE CAST(REPLACE(REPLACE(TRIM(item.BCIPTU), '.', ''), ',', '.') AS DOUBLE)
  END AS assessed_iptu_value,
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
  LATERAL VIEW OUTER EXPLODE(raw.response.dados_imovel) dados_exploded AS item
