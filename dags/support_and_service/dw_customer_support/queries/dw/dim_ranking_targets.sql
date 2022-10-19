SELECT
  id_group AS sk_group,
  MD5(team) AS sk_department,
  team AS department,
  target_resolution,
  target_csat,
  target_sla,
  productivity_target AS target_productivity,
  ra_target_score AS target_ra_score,
  ra_target_solution_rate AS target_ra_solution_rate,
  ra_would_do_business_again_target AS target_ra_would_do_business_again,
  dt_start,
  dt_end,
  NOW() AS ts_load
FROM
  datalake_gsheets_clean.agents_ranking_targets 
