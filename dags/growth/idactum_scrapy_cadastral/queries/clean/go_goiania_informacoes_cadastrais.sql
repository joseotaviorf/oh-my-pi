WITH raw AS (
  SELECT
    registration_number,
    cadastral_info,
    total_records,
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
    datalake_crawled_idactum_houses_raw.go_goiania_informacoes_cadastrais
)
SELECT
  COALESCE(ci.nrinscr, raw.registration_number) AS id_municipal_house,
  'GO' AS state,
  'Goiânia' AS city,
  ci.nmbairro AS neighborhood,
  ci.nmlogradou AS street,
  ci.nrimovel AS address_number,
  ci.incompl AS address_details,
  CAST(ci.areaterr AS DOUBLE) AS lot_area,
  CAST(ci.areaedif AS DOUBLE) AS building_area,
  CAST(ci.areatest AS DOUBLE) AS private_area,
  CAST(ci.vlvenal AS DOUBLE) AS assessed_iptu_value,
  CAST(ci.uso AS STRING) AS usage_purpose,
  CAST(ci.formauso AS STRING) AS usage_type,
  CONCAT(CAST(ci.tpedif1 AS STRING), '/', CAST(ci.tpedif2 AS STRING)) AS kind,
  CAST(ci.x_coord AS DOUBLE) AS latitude,
  CAST(ci.y_coord AS DOUBLE) AS longitude,
  ci.ci AS ci_code,
  ci.nmedificio AS building_name,
  raw.registration_number,
  raw.total_records,
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
  LATERAL VIEW OUTER EXPLODE(raw.cadastral_info) cadastral_info_exploded AS ci
