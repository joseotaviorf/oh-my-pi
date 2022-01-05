--- REGRA REGIONAL 1 CAMPANHA DE SAZONALIDADE Q1 2022

SELECT
  dd.sk_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='RMSP' THEN 0.65672
    WHEN dr.city_group='Rio de Janeiro' THEN 0.22306
    WHEN dr.city_group='Belo Horizonte' THEN 0.06236
    WHEN dr.city_group='Brasília' THEN 0.03522
    WHEN dr.city_group='Porto Alegre' THEN 0.02267
    ELSE 0
  END AS share
FROM
  dim_date dd
  JOIN dim_region dr
    ON dd.date BETWEEN '2021-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'RMSP','Rio de Janeiro','Belo Horizonte',
      'Brasília''Porto Alegre')
GROUP BY 1,2,3

