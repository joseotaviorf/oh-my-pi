SELECT
  DATE(week) AS week,
  week_origin,
  city_group,
  funnel_flow,
  SUM(CAST(REPLACE(target_vb, ',', '') AS DOUBLE)) AS target_vb,
  SUM(CAST(REPLACE(target_vc, ',', '') AS DOUBLE)) AS target_vc,
  SUM(CAST(REPLACE(target_os, ',', '') AS DOUBLE)) AS target_os,
  SUM(CAST(REPLACE(target_oa, ',', '') AS DOUBLE)) AS target_oa,
  SUM(CAST(REPLACE(target_es, ',', '') AS DOUBLE)) AS target_es,
  SUM(CAST(REPLACE(target_cep, ',', '') AS DOUBLE)) AS target_cep,
  SUM(CAST(REPLACE(target_ds, ',', '') AS DOUBLE)) AS target_ds,
  SUM(CAST(REPLACE(target_ca, ',', '') AS DOUBLE)) AS target_ca,
  SUM(CAST(REPLACE(target_cs, ',', '') AS DOUBLE)) AS target_cs
FROM datalake_gsheets_clean.rental_cohort_demand
GROUP BY
  1,
  2,
  3,
  4