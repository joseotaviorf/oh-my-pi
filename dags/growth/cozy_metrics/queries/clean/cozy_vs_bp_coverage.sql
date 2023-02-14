SELECT 
  name AS metric_name,
  project AS project_name,
  project_version,
  value,
  DATE(created_at) AS dt_created
FROM datalake_cozy_metrics_raw.cozy_vs_bp_coverage