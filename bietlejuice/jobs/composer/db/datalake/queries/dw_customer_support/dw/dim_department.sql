SELECT 
  MD5(department) AS sk_department,
  department,
  NULLIF(board,'-') AS board,
  NULLIF(team,'-') AS team,
  NULLIF(journey_step,'-') AS journey_step,
  channel,
  LOWER(front_or_back) AS front_or_back,
  area,
  concentrix_area_name,
  concentrix_area = 'Sim' AS is_concentrix,
  active_department = 'Sim' AS is_active,
  NOW() AS ts_load
FROM 
  datalake_gsheets_clean.department_control
UNION ALL
SELECT DISTINCT
  MD5(ranking) AS sk_department,
  ranking AS department,
  NULL AS board,
  NULL AS team,
  "Offboarding" AS journey_step,
  NULL AS channel,
  NULL AS front_or_back,
  NULL AS area,
  NULL AS concentrix_area_name,
  NULL AS is_concentrix,
  NULL AS is_active,
  NOW() AS ts_load
FROM
  datalake_gsheets_clean.agents_ranking_offboarding