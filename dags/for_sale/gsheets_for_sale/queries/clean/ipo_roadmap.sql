SELECT 
  id,
  task,
  status,
  category
FROM 
  datalake_gsheets_raw.ipo_roadmap
WHERE 
  id IS NOT NULL