select
  id,
  name,
  firstname,
  lastname,
  headline,
  account.subdomain as account_subdomain,
  account.name as account_name,
  job.shortcode as job_short_code,
  job.title as job_title,
  stage,
  disqualified,
  disqualification_reason,
  sourced,
  profile_url,
  email,
  domain,
  created_at,
  updated_at,
  hired_at,
  address,
  phone
from datalake_raw.workable_candidates
;