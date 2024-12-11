SELECT 
  task,
  owner,
  status,
  type,
  INT(duration) AS duration,
  affected_service,
  DATE(start_date) AS dt_start,
  DATE(end_date) AS dt_end,
  notes 
FROM 
  datalake_gsheets_raw.magellan_roadmap
WHERE 
  task IS NOT NULL