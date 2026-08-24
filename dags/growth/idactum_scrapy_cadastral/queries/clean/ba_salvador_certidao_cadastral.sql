SELECT
  response.incricao_imobiliaria AS id_municipal_house,
  response.incricao_imobiliaria AS municipal_inscription,
  'BA' AS state,
  'Salvador' AS city,
  response.bairro AS neighborhood,
  response.logradouro AS street,
  COALESCE(response.numero_porta, response.numero_metrico) AS address_number,
  response.cep AS zipcode,
  response.complemento_endereco AS address_details,
  CASE
    WHEN response.area_terreno IS NULL OR TRIM(response.area_terreno) = '' THEN NULL
    ELSE CAST(REPLACE(REPLACE(TRIM(response.area_terreno), '.', ''), ',', '.') AS DOUBLE)
  END AS lot_area,
  CASE
    WHEN response.area_construida IS NULL OR TRIM(response.area_construida) = '' THEN NULL
    ELSE CAST(REPLACE(REPLACE(TRIM(response.area_construida), '.', ''), ',', '.') AS DOUBLE)
  END AS building_area,
  response.utilizacao AS usage_purpose,
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
  datalake_crawled_idactum_houses_raw.ba_salvador_certidao_cadastral
