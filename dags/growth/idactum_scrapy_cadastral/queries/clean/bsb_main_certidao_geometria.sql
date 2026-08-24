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
    datalake_crawled_idactum_houses_raw.bsb_main_certidao_geometria
)
SELECT
  COALESCE(feature.properties.iptu_imovel, CAST(feature.properties.objectid AS STRING)) AS id_municipal_house,
  feature.properties.iptu_imovel AS municipal_inscription,
  'DF' AS state,
  'Brasilia' AS city,
  feature.properties.lt_nome AS neighborhood,
  feature.properties.iptu_endereco AS address_details,
  feature.properties.lt_cep AS zipcode,
  CAST(feature.properties.iptu_area_terr AS DOUBLE) AS lot_area,
  CAST(feature.properties.iptu_areac_dec AS DOUBLE) AS building_area,
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
  LATERAL VIEW OUTER EXPLODE(raw.response.features) features_exploded AS feature
