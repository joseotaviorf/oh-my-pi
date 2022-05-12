SELECT
  dd.sk_date AS id_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='Curitiba' THEN 0.5352
    WHEN dr.city_group='Campinas' THEN 0.3347
    WHEN dr.city_group='Santos' THEN 0.1301
    ELSE 0
  END AS share,
  'social' AS funnel_side
FROM
  dim_date dd
  JOIN dim_region dr
    ON dd.date BETWEEN '2022-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'Curitiba','Campinas','Santos'
    )
GROUP BY 1,2,3,4