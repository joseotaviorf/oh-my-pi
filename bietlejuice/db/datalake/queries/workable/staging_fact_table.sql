select
  j.id as sk_job,
  coalesce(c.id, '-1') as sk_candidate
from datalake_clean.workable_jobs j
left join datalake_clean.workable_candidates c
  on j.short_code = c.job_short_code
;