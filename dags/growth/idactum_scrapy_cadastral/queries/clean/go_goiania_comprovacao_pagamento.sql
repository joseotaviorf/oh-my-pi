SELECT
  response._inscricao AS id_municipal_house,
  response.inscricao AS inscricao_raw,
  'GO' AS state,
  'Goiânia' AS city,
  response.endereco AS address_details,
  response.setor AS neighborhood,
  response.cpf_cnpj AS owner_document,
  response.numero_certidao AS certificate_number,
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
  datalake_crawled_idactum_houses_raw.go_goiania_comprovacao_pagamento
