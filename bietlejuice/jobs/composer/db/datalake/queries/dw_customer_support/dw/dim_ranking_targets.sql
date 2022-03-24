SELECT
  id_group AS sk_group,
  MD5(team) AS sk_department,
  team AS department,
  company,
  target_resolution,
  target_csat,
  target_frt,
  productivity_target AS target_productivity,
  ra_would_back_make_business_target AS target_reclameaqui_would_back_make_business,
  dt_start,
  dt_end,
  NOW() AS ts_load
FROM
  datalake_gsheets_clean.agents_ranking_targets