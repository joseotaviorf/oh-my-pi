SELECT
  id,
  houseId AS id_house,
  businessContext AS business_context,
  p10 AS p_10,
  p20 AS p_20,
  p30 AS p_30,
  p40 AS p_40,
  p50 AS p_50,
  p60 AS p_60,
  p70 AS p_70,
  p80 AS p_80,
  p90 AS p_90,
  certainty,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM
  datalake_ebdb_raw.housepredictedprice
