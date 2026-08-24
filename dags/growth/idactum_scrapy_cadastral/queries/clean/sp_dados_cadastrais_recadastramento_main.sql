SELECT
  response.NumIPTU AS id_municipal_house,
  response.NumIPTU AS municipal_inscription,
  'SP' AS state,
  'Sao Paulo' AS city,
  response.Bairro AS neighborhood,
  response.Endereco AS street,
  response.Numero AS address_number,
  response.Complemento AS address_details,
  response.CepImovel AS zipcode,
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
  datalake_crawled_idactum_houses_raw.sp_dados_cadastrais_recadastramento_main
