WITH raw AS (
  SELECT
    response,
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
    datalake_crawled_idactum_houses_raw.sp_santo_andre_itbi
)
SELECT
  item.matricula AS id_municipal_house,
  item.matricula AS real_estate_registry,
  'SP' AS state,
  'Santo Andre' AS city,
  item.endereco AS address_details,
  item.cartorio AS real_estate_register,
  CASE
    WHEN item.valor_pago IS NULL OR TRIM(item.valor_pago) = '' THEN NULL
    ELSE CAST(
      REPLACE(
        REPLACE(REPLACE(TRIM(item.valor_pago), 'R$', ''), '.', ''),
        ',',
        '.'
      ) AS DOUBLE
    )
  END AS assessed_itbi_value,
  CASE
    WHEN item.valor_venal IS NULL OR TRIM(item.valor_venal) = '' THEN NULL
    ELSE CAST(
      REPLACE(
        REPLACE(REPLACE(TRIM(item.valor_venal), 'R$', ''), '.', ''),
        ',',
        '.'
      ) AS DOUBLE
    )
  END AS assessed_iptu_value,
  CASE
    WHEN item.area_terreno IS NULL OR TRIM(item.area_terreno) = '' THEN NULL
    ELSE CAST(REPLACE(REPLACE(TRIM(item.area_terreno), ' M2', ''), ',', '.') AS DOUBLE)
  END AS lot_area,
  CASE
    WHEN item.area_construcao IS NULL OR TRIM(item.area_construcao) = '' THEN NULL
    ELSE CAST(REPLACE(REPLACE(TRIM(item.area_construcao), ' M2', ''), ',', '.') AS DOUBLE)
  END AS building_area,
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
  LATERAL VIEW OUTER EXPLODE(raw.response) response_exploded AS item
