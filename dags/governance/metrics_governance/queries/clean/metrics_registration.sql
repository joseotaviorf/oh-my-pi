SELECT
  name as metric_name,
  acronym as metric_acronym,
  description as metric_description,
  business_stage,
  calculation as metric_calculation,
  company_line,
  hierarchy_level,
  link_to_metric,
  approved_by,
  created_by,
  updated_by,
  maturity_level,
  observations,
  is_additive,
  has_datamart,
  datamart_name,
  metric_source,
  is_active,
  ts_created,
  ts_updated,
  ts_load,
  year,
  month,
  day
FROM
    datalake_metrics_governance_raw.metrics_registration
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
