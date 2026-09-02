WITH raw AS (
  SELECT
    sql,
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
    datalake_crawled_idactum_houses_raw.sp_santo_andre_iptu
)
SELECT
  item.classificacao_fiscal AS id_municipal_house,
  item.classificacao_fiscal AS municipal_inscription,
  raw.sql AS fiscal_classification_query,
  item.lancamento AS iptu_bill_number,
  'SP' AS state,
  'Santo Andre' AS city,
  item.endereco AS address_details,
  item.loteamento_quadra_lote AS block_lot,
  item.exercicio AS tax_year,
  item.grupo_lancamento AS usage_purpose,
  CASE
    WHEN item.area_terreno IS NULL OR TRIM(item.area_terreno) = '' THEN NULL
    ELSE CAST(REPLACE(REPLACE(TRIM(item.area_terreno), '.', ''), ',', '.') AS DOUBLE)
  END AS lot_area,
  CASE
    WHEN item.area_predio IS NULL OR TRIM(item.area_predio) = '' THEN NULL
    ELSE CAST(REPLACE(REPLACE(TRIM(item.area_predio), '.', ''), ',', '.') AS DOUBLE)
  END AS building_area,
  CASE
    WHEN item.valor_venal_predio IS NULL
      AND item.valor_venal_terreno IS NULL THEN NULL
    ELSE COALESCE(
      CASE
        WHEN item.valor_venal_predio IS NULL OR TRIM(item.valor_venal_predio) = '' THEN 0
        ELSE CAST(
          REPLACE(REPLACE(TRIM(item.valor_venal_predio), '.', ''), ',', '.') AS DOUBLE
        )
      END,
      0
    ) + COALESCE(
      CASE
        WHEN item.valor_venal_terreno IS NULL OR TRIM(item.valor_venal_terreno) = '' THEN 0
        ELSE CAST(
          REPLACE(REPLACE(TRIM(item.valor_venal_terreno), '.', ''), ',', '.') AS DOUBLE
        )
      END,
      0
    )
  END AS assessed_iptu_value,
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
