SELECT
  dd.sk_date AS id_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='RMSP' THEN 0.41
    WHEN dr.city_group='Rio de Janeiro' THEN 0.20
    WHEN dr.city_group='Belo Horizonte' THEN 0.08
    WHEN dr.city_group='Porto Alegre' THEN 0.05
    WHEN dr.city_group='Brasília' THEN 0.11
    WHEN dr.city_group='Curitiba' THEN 0.06
    WHEN dr.city_group='Florianópolis' THEN 0.01
    WHEN dr.city_group='Campinas' THEN 0.04
    WHEN dr.city_group='Santos' THEN 0.02
    WHEN dr.city_group='Sorocaba' THEN 0.01
    WHEN dr.city_group='Uberlândia' THEN 0.01
    ELSE 0
  END AS share,
  'social' AS funnel_side
FROM
  aux_date dd
  JOIN aux_region dr
    ON dd.date BETWEEN '2022-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'RMSP','Rio de Janeiro','Belo Horizonte',
      'Porto Alegre','Brasília','Curitiba',
      'Florianópolis','Campinas','Santos',
      'Sorocaba','Uberlândia'
    )
GROUP BY 1,2,3,4