WITH raw AS (
  SELECT
    neighborhood_code,
    neighborhood_name,
    registrations,
    total_registrations,
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
    datalake_crawled_idactum_houses_raw.pa_belem_certidao_cadastro_bairros
)
SELECT
  reg.inscricao AS id_municipal_house,
  reg.inscricao AS municipal_inscription,
  'PA' AS state,
  'Belem' AS city,
  raw.neighborhood_code,
  raw.neighborhood_name,
  reg.sequencial AS registration_sequential,
  reg.endereco AS address_details,
  reg.situacao AS registration_status,
  raw.total_registrations,
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
  LATERAL VIEW OUTER EXPLODE(raw.registrations) registrations_exploded AS reg
