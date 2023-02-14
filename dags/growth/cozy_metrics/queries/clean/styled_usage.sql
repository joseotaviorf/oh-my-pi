WITH exploded_tab AS (
  SELECT 
    created_at, 
    project, 
    EXPLODE(FROM_JSON(value, 'map<string, string>')) AS (key, value)
  FROM datalake_cozy_metrics_raw.styled_usage
),
total_tab AS (
  SELECT 
      created_at, 
      project, 
      EXPLODE(FROM_JSON(value, 'ARRAY<map<string,string>>')) AS components
  FROM exploded_tab
  WHERE key = 'files'
)
SELECT 
  s.name AS metric_name,
  s.project AS project_name,
  s.project_version,
  t1.components['components'] AS styled_components,
  t1.components['path'] AS path_components,
  t2.value AS total_components,
  DATE(s.created_at) AS dt_created
FROM datalake_cozy_metrics_raw.styled_usage s
LEFT JOIN total_tab t1
  ON s.created_at = t1.created_at
    AND s.project = t1.project
LEFT JOIN exploded_tab t2
  ON s.created_at = t2.created_at
    AND s.project = t2.project
WHERE 
  t2.key = 'total'