--- REGRA REGIONAL 3 CAMPANHA DE SAZONALIDADE Q1 2022

SELECT
  dd.sk_date AS id_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='Goiânia' THEN 0.78125
    WHEN dr.city_group='Vitória' THEN 0.0625
    WHEN dr.city_group='São José dos Campos' THEN 0.03125
    WHEN dr.city_group='São José do Rio Preto' THEN 0.03125
    WHEN dr.city_group='Ribeirão Preto' THEN 0.03125
    WHEN dr.city_group='Mogi das Cruzes' THEN 0.03125
    WHEN dr.city_group='RMSP' THEN 0.03125
    ELSE 0
  END AS share,
  'social' AS funnel_side
FROM
  dim_date dd
  JOIN dim_region dr
    ON dd.date BETWEEN '2021-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'Goiânia','Vitória','São José dos Campos',
      'São José do Rio Preto','Ribeirão Preto','Mogi das Cruzes',
      'RMSP')
GROUP BY 1,2,3,4