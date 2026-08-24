SELECT
  response.inscricao AS id_municipal_house,
  response.inscricao AS municipal_inscription,
  'DF' AS state,
  COALESCE(response.cidade, 'Brasilia') AS city,
  response.bairro_de_correspondencia AS neighborhood,
  response.endereco_do_imovel AS address_details,
  CAST(response.cep_do_imovel AS STRING) AS zipcode,
  CAST(response.area_terreno AS DOUBLE) AS lot_area,
  CAST(response.area_da_construcao_do_alvara AS DOUBLE) AS building_area,
  CAST(response.area_declarada AS DOUBLE) AS private_area,
  response.natureza_do_imovel AS usage_purpose,
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
  datalake_crawled_idactum_houses_raw.bsb_main_fichas
