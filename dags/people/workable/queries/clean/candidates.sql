SELECT
  -- ids
  id,
  -- non-metrics
  name,
  firstname AS first_name,
  lastname AS last_name,
  headline,
  account.subdomain AS account_subdomain,
  account.name AS account_name,
  job.title AS job_title,
  job.shortcode AS job_shortcode,
  stage,
  disqualification_reason,
  profile_url,
  email,
  domain,
  address,
  phone,
  -- metrics
  BOOLEAN(disqualified) AS is_disqualified,
  BOOLEAN(sourced) AS is_sourced,
  -- ts
  TO_TIMESTAMP(created_at) AS ts_created,
  TO_TIMESTAMP(updated_at) AS ts_updated,
  TO_TIMESTAMP(hired_at) AS ts_hired,
  NOW() AS ts_load,
  year,
  month,
  day
FROM
  datalake_workable_raw.candidates
WHERE 
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')