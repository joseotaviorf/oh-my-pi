SELECT 
  MD5(department) AS sk_department,
  department,
  NULLIF(board,'-') AS board,
  NULLIF(team,'-') AS team,
  NULLIF(journey_step,'-') AS journey_step,
  channel,
  concentrix_area_name,
  concentrix_area = 'Sim' AS is_concentrix,
  active_department = 'Sim' AS is_active,
  NOW() AS ts_load
FROM 
  datalake_gsheets_clean.department_control