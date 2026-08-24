SELECT
  COALESCE(response.dados_cadastrais.matricula, response.dados_cadastrais.referencia_anterior) AS id_municipal_house,
  response.dados_cadastrais.matricula AS real_estate_registry,
  'RJ' AS state,
  'Niteroi' AS city,
  response.proprietario.bairro AS neighborhood,
  response.proprietario.nomepri AS street,
  CAST(response.proprietario.j39_numero AS STRING) AS address_number,
  response.proprietario.j39_compl AS address_details,
  response.proprietario.enderecoimovel AS property_address,
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
  datalake_crawled_idactum_houses_raw.rj_niteroi_e_cidade
