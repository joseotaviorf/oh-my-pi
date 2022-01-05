--Social cost share
SELECT
  dd.sk_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='RMSP' THEN 0.55009
    WHEN dr.city_group='Rio de Janeiro' THEN 0.18684
    WHEN dr.city_group='Campinas' THEN 0.05055
    WHEN dr.city_group='Belo Horizonte' THEN 0.05221
    WHEN dr.city_group='Brasília' THEN 0.0295
    WHEN dr.city_group='Goiânia' THEN 0.05761
    WHEN dr.city_group='Porto Alegre' THEN 0.01899
    WHEN dr.city_group='Curitiba' THEN 0.02388
    WHEN dr.city_group='Florianópolis' THEN 0.01395
    WHEN dr.city_group='Recife' THEN 0.0035
    WHEN dr.city_group='Salvador' THEN 0.0035
    WHEN dr.city_group='Santos' THEN 0.00338
    WHEN dr.city_group='Vitória' THEN 0.002
    WHEN dr.city_group='Ribeirão Preto' THEN 0.001
    WHEN dr.city_group='São José dos Campos' THEN 0.001
    WHEN dr.city_group='São José do Rio Preto' THEN 0.001
    WHEN dr.city_group='Sorocaba' THEN 0.001
    ELSE 0
  END AS share
FROM
  dim_date dd
  JOIN dim_region dr
    ON dd.date BETWEEN '2021-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'RMSP','Rio de Janeiro','Campinas','Belo Horizonte',
      'Brasília','Goiânia','Porto Alegre','Curitiba',
      'Florianópolis','Recife','Salvador','Santos',
      'Vitória','Ribeirão Preto','São José dos Campos',
      'São José do Rio Preto', 'Sorocaba')
GROUP BY 1,2,3
