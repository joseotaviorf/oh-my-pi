select
  id as sk_job,
  title,
  full_title,
  short_code,
  code,
  state,
  department,
  url,
  application_url,
  short_link,
  location_country,
  location_country_code,
  location_region,
  location_city,
  location_zip_code,
  location_telecommuting,
  created_at
from datalake_clean.workable_jobs
;