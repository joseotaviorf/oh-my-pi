WITH raw AS (
  SELECT
    CAST(neighborhood_id AS BIGINT) AS neighborhood_id,
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
    datalake_crawled_idactum_houses_raw.go_goiania_cadastro_imobiliario
)
SELECT
  reg.registration_number AS id_municipal_house,
  reg.ci AS ci_code,
  'GO' AS state,
  'Goiânia' AS city,
  raw.neighborhood_id,
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
