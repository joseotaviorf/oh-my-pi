WITH exploded_table AS (
  SELECT 
    created_at, 
    name, 
    project, 
    project_version, 
    EXPLODE(FROM_JSON(value, 'map<string, float>'))  AS (key, value)
  FROM datalake_cozy_metrics_raw.count_cozy_imports
)

SELECT 
  name AS metric_name,
  project AS project_name,
  project_version,
  REPLACE(REPLACE(key,'@quintoandar/cozy-core/',''), '/', '_') AS items,
  value AS count_imports,
  DATE(created_at) AS dt_created
FROM exploded_table