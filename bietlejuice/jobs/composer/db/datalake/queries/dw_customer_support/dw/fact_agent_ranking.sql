SELECT
  id_agent AS sk_agent,
  MD5(department) AS sk_department,
  id_group AS sk_group,
  multiplication_factor,
  ranking_score,
  ranking_quartile,
  ranking_percent_position,
  ranking_position,
  dt_ranking_week,
  YEAR(dt_ranking_week) AS year,
  MONTH(dt_ranking_week) AS month,
  DAY(dt_ranking_week) AS day
FROM
  datalake_analyst_ranking.ranking
WHERE
  dt_ranking_week = DATE(DATE_TRUNC('week', '{year}-{month}-{day}'))