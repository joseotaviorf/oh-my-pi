SELECT
  -- ids
  id,
  -- non-metrics
  shortcode,
  code,
  title,
  full_title,
  state,
  department,
  location.location_str AS location_str,
  location.country AS location_country, 
  location.country_code AS location_country_code,
  location.region AS location_region,
  location.region_code AS location_region_code,
  location.city AS location_city,
  location.zip_code AS location_zip_code,
  location.telecommuting AS location_telecommuting,
  location.workplace_type AS location_workplace_type,
  salary.salary_currency AS salary_currency,
  url,
  application_url,
  shortlink,
  -- nested
  department_hierarchy,
  locations,
  -- metrics
  FLOAT(salary.salary_from) AS salary_from,
  FLOAT(salary.salary_to) AS salary_to,
  -- ts
  to_timestamp(created_at) AS ts_created,
  NOW() AS ts_load
FROM
  datalake_workable_raw.jobs