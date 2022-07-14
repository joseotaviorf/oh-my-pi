SELECT
  dd.sk_date AS id_date,
  dr.city_group,
  CASE
    WHEN dr.city_group='Florianópolis' THEN 0.2740
    WHEN dr.city_group='Sorocaba' THEN 0.3672
    WHEN dr.city_group='Uberlândia' THEN 0.3588
    ELSE 0
  END AS share,
  'social' AS funnel_side
FROM
  dim_date dd
  JOIN dim_region dr
    ON dd.date BETWEEN '2022-01-01' AND CURRENT_DATE
    AND dr.city_group IN (
      'Florianópolis','Sorocaba','Uberlândia'
    )
GROUP BY 1,2,3,4