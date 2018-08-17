select
  id as sk_candidate,
  name,
  first_name,
  last_name,
  rpad(headline, 200, 'headline') as headline, -- some candidates insert an entire description of their careers/hobbies
  account_subdomain,
  account_name,
  stage,
  disqualified,
  disqualification_reason,
  sourced,
  profile_url,
  email,
  domain,
  created_at,
  updated_at,
  hired_at
from datalake_clean.workable_candidates
;