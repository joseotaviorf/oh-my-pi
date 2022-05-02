SELECT
  dd.sk_date AS id_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='Goiânia' THEN 0.3537
    WHEN dr.city_group='Vitória' THEN 0.0832
    WHEN dr.city_group='Ribeirão Preto' THEN 0.1560
    WHEN dr.city_group='São José dos Campos' THEN 0.1624
    WHEN dr.city_group='São José do Rio Preto' THEN 0.1053
    WHEN dr.city_group='Mogi das Cruzes' THEN 0.10
    WHEN dr.city_group='RMSP' THEN 0.0394
    ELSE 0
  END AS share,
  'social' AS funnel_side
FROM
  aux_date dd
  JOIN aux_region dr
    ON dd.date BETWEEN '2022-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'Goiânia','Vitória','São José dos Campos',
      'São José do Rio Preto','Ribeirão Preto','Mogi das Cruzes',
      'RMSP')
GROUP BY 1,2,3,4