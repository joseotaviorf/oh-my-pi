SELECT
  COALESCE(response.inscricao_cadastral, response.cdc) AS id_municipal_house,
  response.inscricao_cadastral AS municipal_inscription,
  response.cdc AS cdc,
  'SP' AS state,
  'Osasco' AS city,
  response.cartorio_de_registro AS real_estate_register,
  CASE
    WHEN response.valor_da_transacao IS NULL OR TRIM(response.valor_da_transacao) = '' THEN NULL
    ELSE CAST(
      REPLACE(
        REPLACE(TRIM(response.valor_da_transacao), '.', ''),
        ',',
        '.'
      ) AS DOUBLE
    )
  END AS assessed_itbi_value,
  CASE
    WHEN response.valor_venal_do_imovel IS NULL OR TRIM(response.valor_venal_do_imovel) = '' THEN NULL
    ELSE CAST(
      REPLACE(
        REPLACE(TRIM(response.valor_venal_do_imovel), '.', ''),
        ',',
        '.'
      ) AS DOUBLE
    )
  END AS assessed_iptu_value,
  CASE
    WHEN response.valor_venal_da_edificacao IS NULL OR TRIM(response.valor_venal_da_edificacao) = '' THEN NULL
    ELSE CAST(
      REPLACE(
        REPLACE(TRIM(response.valor_venal_da_edificacao), '.', ''),
        ',',
        '.'
      ) AS DOUBLE
    )
  END AS building_assessed_value,
  response.natureza_da_operacao AS transaction_nature,
  response.proprietario AS owner_name,
  response.adquirente AS buyer_name,
  response.situacao AS payment_status,
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
  datalake_crawled_idactum_houses_raw.sp_osasco_itbi
