--- REGRA REGIONAL 2 CAMPANHA DE SAZONALIDADE Q1 2022

SELECT
  dd.sk_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='Campinas' THEN 0.53912
    WHEN dr.city_group='Curitiba' THEN 0.25468
    WHEN dr.city_group='Florianópolis' THEN 0.14879
    WHEN dr.city_group='Santos' THEN 0.03608
    WHEN dr.city_group='Sorocaba' THEN 0.01066
    WHEN dr.city_group='Uberlândia' THEN 0.01066
    ELSE 0
  END AS share
FROM
  dim_date dd
  JOIN dim_region dr
    ON dd.date BETWEEN '2021-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'Campinas','Curitiba','Florianópolis',
      'Santos','Sorocaba','Uberlândia')
GROUP BY 1,2,3