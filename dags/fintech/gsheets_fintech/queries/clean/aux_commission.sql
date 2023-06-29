SELECT
  commission_type,
  region,
  CAST(faixa_20 AS INTEGER) AS range_20,
  CAST(faixa_30 AS INTEGER) AS range_30,
  CAST(faixa_40 AS INTEGER) AS range_40,
  CAST(faixa_50 AS INTEGER) AS range_50,
  DATE(vigencia_inicio) AS dt_started_validity,
  DATE(vigencia_fim) AS dt_ended_validity
FROM
  datalake_gsheets_raw.aux_commission
