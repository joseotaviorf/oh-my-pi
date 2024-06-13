SELECT 
  -- ids
  id,
  -- non-ids
  job.id AS id_job,
  department.id AS id_department,
  requester.id AS id_requester,
  owner.id AS id_owner,
  candidate_id AS id_candidate,
  -- non-metrics
  code,
  job.shortcode AS job_shortcode,
  job.title AS job_title,
  department.name AS department_name,
  location.location_str AS location_str,
  location.country AS location_country,
  location.country_code AS location_country_code,
  location.region AS location_region,
  location.region_code AS location_region_code,
  location.city AS location_city,
  location.zip_code AS location_zip_code,
  requester.name AS requester_name,
  owner.name AS owner_name,
  salary_range.frequency AS salary_range_frequency,
  salary_range.currency_iso AS salary_range_currency_iso,
  salary.frequency AS salary_frequency,
  salary.currency_iso AS salary_currency_iso,
  employment_type,
  reason,
  state,
  -- nested
  requisition_attributes,
  approval_groups,
  -- metrics
  FLOAT(salary_range.from) AS salary_range_from,
  FLOAT(salary_range.to) AS salary_range_to,
  FLOAT(salary.amount) AS salary_amount,
  -- dt
  DATE(plan_date) AS dt_plan,
  DATE(start_date) AS dt_start,
  -- ts
  now() AS ts_load
FROM
  datalake_workable_raw.requisitions