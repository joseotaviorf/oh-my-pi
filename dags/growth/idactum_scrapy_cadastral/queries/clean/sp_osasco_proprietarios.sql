SELECT
  TRANSFORM(
    response,
    item -> STRUCT(
      item.cpf_cnpj AS cpf_cnpj,
      item.nome AS nome,
      CAST(item.percentual_posse AS STRING) AS percentual_posse
    )
  ) AS response,
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
  datalake_crawled_idactum_houses_raw.sp_osasco_proprietarios
