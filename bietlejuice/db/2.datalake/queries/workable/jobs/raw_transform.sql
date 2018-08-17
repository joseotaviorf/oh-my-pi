select
  id,
  title,
  full_title,
  shortcode,
  code,
  state,
  department,
  url,
  application_url,
  shortlink,
  location.country as location_country,
  location.country_code as location_country_code,
  location.region as location_region,
  location.region_code as location_region_code,
  location.city as location_city,
  location.zip_code as location_zip_code,
  location.telecommuting as location_telecommuting,
  created_at
from datalake_raw.workable_jobs
;