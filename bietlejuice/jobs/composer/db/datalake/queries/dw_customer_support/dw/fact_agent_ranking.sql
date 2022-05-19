SELECT
  id_agent AS sk_agent,
  MD5(department) AS sk_department,
  id_group AS sk_group,
  CAST(DATE_FORMAT(dt_ranking_week, 'yyyyMMdd') AS BIGINT) AS sk_date,
  agent_age_in_months,
  productivity_achievement,
  sla_achievement,
  csat_achievement,
  resolution_achievement,
  ra_would_do_business_again_achievement,
  ra_score_achievement,
  ra_solutionra_solution_achievement,
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