SELECT
  name,
  acronym,
  description,
  company_line,
  business_stage,
  hierarchy_level,
  maturity_level,
  created_by,
  approved_by,
  is_additive,
  link_to_metric,
  calculation,
  observations,
  year,
  month,
  day
FROM
    datalake_metrics_governance_raw.metrics_registration
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
