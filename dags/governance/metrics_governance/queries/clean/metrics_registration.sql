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
  maturity_level,
  observations,
  is_additive,
  has_datamart,
  datamart_name,
  is_active,
  ts_load,
  year,
  month,
  day
FROM
    datalake_metrics_governance_raw.metrics_registration
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
